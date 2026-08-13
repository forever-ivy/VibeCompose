//! Cross-platform microphone capture to mono PCM WAV.
//!
//! Mirrors the Swift `AudioRecorder` contract: mono 16-bit WAV at the
//! configured target rate (24 kHz by default), a hard maximum duration, and
//! deletion of cancelled temporary recordings. Capture runs at the device's
//! native rate and is linearly resampled to the target rate on stop.

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use thiserror::Error;

use vc_core::pipeline::RecordedAudio;

#[derive(Debug, Error)]
pub enum RecorderError {
    #[error("no input device is available")]
    NoInputDevice,
    #[error("the input device rejected the requested configuration: {0}")]
    UnsupportedConfiguration(String),
    #[error("audio stream failed: {0}")]
    Stream(String),
    #[error("writing the recording failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("recording was already stopped")]
    AlreadyStopped,
}

struct SharedCapture {
    samples: Mutex<Vec<f32>>,
    /// RMS level (scaled by 1000) for HUD feedback.
    level_milli: AtomicU32,
    overflowed: AtomicBool,
}

/// An in-progress recording. Dropping without `stop()` discards the capture.
pub struct RecordingHandle {
    shared: Arc<SharedCapture>,
    stop_tx: Option<std::sync::mpsc::Sender<()>>,
    thread: Option<std::thread::JoinHandle<Result<(), RecorderError>>>,
    device_sample_rate: u32,
    target_sample_rate: u32,
    started_at: std::time::Instant,
    max_duration_seconds: u32,
    output_dir: PathBuf,
}

impl RecordingHandle {
    /// Current input level in 0.0–1.0 for HUD visualization.
    pub fn level(&self) -> f32 {
        self.shared.level_milli.load(Ordering::Relaxed) as f32 / 1000.0
    }

    pub fn elapsed_ms(&self) -> i64 {
        self.started_at.elapsed().as_millis() as i64
    }

    pub fn reached_limit(&self) -> bool {
        self.elapsed_ms() >= i64::from(self.max_duration_seconds) * 1000
    }

    /// Stops capture and writes `vibecompose-<uuid>.wav` (mono s16 target
    /// rate) into the output directory.
    pub fn stop(mut self) -> Result<RecordedAudio, RecorderError> {
        self.finish_stream()?;
        let samples = {
            let guard = self.shared.samples.lock().unwrap_or_else(|e| e.into_inner());
            guard.clone()
        };
        let resampled = resample_linear(&samples, self.device_sample_rate, self.target_sample_rate);
        let duration_ms =
            (resampled.len() as i64 * 1000) / i64::from(self.target_sample_rate.max(1));

        std::fs::create_dir_all(&self.output_dir)?;
        let path = self
            .output_dir
            .join(format!("vibecompose-{}.wav", uuid_v4_string()));
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: self.target_sample_rate,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::create(&path, spec)
            .map_err(|e| RecorderError::Stream(e.to_string()))?;
        for sample in &resampled {
            let clamped = (sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
            writer
                .write_sample(clamped)
                .map_err(|e| RecorderError::Stream(e.to_string()))?;
        }
        writer
            .finalize()
            .map_err(|e| RecorderError::Stream(e.to_string()))?;

        Ok(RecordedAudio {
            wav_path: path,
            duration_ms,
            sample_rate_hz: self.target_sample_rate,
        })
    }

    /// Cancels the recording; no file is written.
    pub fn cancel(mut self) {
        let _ = self.finish_stream();
    }

    fn finish_stream(&mut self) -> Result<(), RecorderError> {
        let Some(stop_tx) = self.stop_tx.take() else {
            return Err(RecorderError::AlreadyStopped);
        };
        let _ = stop_tx.send(());
        if let Some(thread) = self.thread.take() {
            match thread.join() {
                Ok(result) => result?,
                Err(_) => return Err(RecorderError::Stream("capture thread panicked".into())),
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub struct AudioRecorder {
    pub target_sample_rate: u32,
    pub max_duration_seconds: u32,
    pub output_dir: PathBuf,
}

impl AudioRecorder {
    pub fn new(target_sample_rate: u32, max_duration_seconds: u32, output_dir: PathBuf) -> Self {
        Self {
            target_sample_rate,
            max_duration_seconds,
            output_dir,
        }
    }

    /// Starts capturing from the default input device. The cpal stream is not
    /// `Send`, so it lives on a dedicated thread owned by the handle.
    pub fn start(&self) -> Result<RecordingHandle, RecorderError> {
        let host = cpal::default_host();
        let device = host.default_input_device().ok_or(RecorderError::NoInputDevice)?;
        let config = device
            .default_input_config()
            .map_err(|e| RecorderError::UnsupportedConfiguration(e.to_string()))?;
        let device_sample_rate = config.sample_rate().0;
        let channels = config.channels() as usize;
        let sample_format = config.sample_format();
        let stream_config: cpal::StreamConfig = config.into();

        let shared = Arc::new(SharedCapture {
            samples: Mutex::new(Vec::with_capacity(device_sample_rate as usize * 30)),
            level_milli: AtomicU32::new(0),
            overflowed: AtomicBool::new(false),
        });
        let max_samples =
            device_sample_rate as usize * self.max_duration_seconds as usize;

        let (stop_tx, stop_rx) = std::sync::mpsc::channel::<()>();
        let (ready_tx, ready_rx) = std::sync::mpsc::channel::<Result<(), RecorderError>>();
        let capture_shared = Arc::clone(&shared);

        let thread = std::thread::Builder::new()
            .name("vc-audio-capture".into())
            .spawn(move || -> Result<(), RecorderError> {
                let build_result = match sample_format {
                    cpal::SampleFormat::F32 => build_stream::<f32>(
                        &device,
                        &stream_config,
                        channels,
                        max_samples,
                        capture_shared,
                    ),
                    cpal::SampleFormat::I16 => build_stream::<i16>(
                        &device,
                        &stream_config,
                        channels,
                        max_samples,
                        capture_shared,
                    ),
                    cpal::SampleFormat::U16 => build_stream::<u16>(
                        &device,
                        &stream_config,
                        channels,
                        max_samples,
                        capture_shared,
                    ),
                    other => Err(RecorderError::UnsupportedConfiguration(format!(
                        "unsupported sample format {other:?}"
                    ))),
                };
                let stream = match build_result {
                    Ok(stream) => {
                        let _ = ready_tx.send(Ok(()));
                        stream
                    }
                    Err(error) => {
                        let message = error.to_string();
                        let _ = ready_tx.send(Err(error));
                        return Err(RecorderError::Stream(message));
                    }
                };
                stream.play().map_err(|e| RecorderError::Stream(e.to_string()))?;
                // Block until stop; the stream drops (and closes) on return.
                let _ = stop_rx.recv();
                Ok(())
            })
            .map_err(|e| RecorderError::Stream(e.to_string()))?;

        match ready_rx.recv() {
            Ok(Ok(())) => {}
            Ok(Err(error)) => {
                let _ = thread.join();
                return Err(error);
            }
            Err(_) => {
                let _ = thread.join();
                return Err(RecorderError::Stream("capture thread exited early".into()));
            }
        }

        Ok(RecordingHandle {
            shared,
            stop_tx: Some(stop_tx),
            thread: Some(thread),
            device_sample_rate,
            target_sample_rate: self.target_sample_rate,
            started_at: std::time::Instant::now(),
            max_duration_seconds: self.max_duration_seconds,
            output_dir: self.output_dir.clone(),
        })
    }
}

fn build_stream<T>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    channels: usize,
    max_samples: usize,
    shared: Arc<SharedCapture>,
) -> Result<cpal::Stream, RecorderError>
where
    T: cpal::SizedSample + cpal::Sample,
    f32: cpal::FromSample<T>,
{
    let error_shared = Arc::clone(&shared);
    device
        .build_input_stream(
            config,
            move |data: &[T], _| {
                let mut mono = Vec::with_capacity(data.len() / channels.max(1));
                let mut sum_squares = 0.0f32;
                for frame in data.chunks(channels.max(1)) {
                    let mixed: f32 = frame
                        .iter()
                        .map(|s| <f32 as cpal::FromSample<T>>::from_sample_(*s))
                        .sum::<f32>()
                        / channels.max(1) as f32;
                    sum_squares += mixed * mixed;
                    mono.push(mixed);
                }
                if !mono.is_empty() {
                    let rms = (sum_squares / mono.len() as f32).sqrt();
                    shared
                        .level_milli
                        .store((rms.clamp(0.0, 1.0) * 1000.0) as u32, Ordering::Relaxed);
                }
                let mut samples = shared.samples.lock().unwrap_or_else(|e| e.into_inner());
                let remaining = max_samples.saturating_sub(samples.len());
                if remaining == 0 {
                    shared.overflowed.store(true, Ordering::Relaxed);
                    return;
                }
                let take = remaining.min(mono.len());
                samples.extend_from_slice(&mono[..take]);
            },
            move |error| {
                error_shared.overflowed.store(true, Ordering::Relaxed);
                tracing::error!("audio input stream error: {error}");
            },
            None,
        )
        .map_err(|e| RecorderError::Stream(e.to_string()))
}

/// Linear resampling is sufficient for speech-to-text input; the upstream
/// models are robust to it and it avoids a heavyweight DSP dependency on the
/// hot path.
fn resample_linear(input: &[f32], from_rate: u32, to_rate: u32) -> Vec<f32> {
    if input.is_empty() || from_rate == 0 || to_rate == 0 || from_rate == to_rate {
        return input.to_vec();
    }
    let ratio = f64::from(from_rate) / f64::from(to_rate);
    let output_len = ((input.len() as f64) / ratio).floor() as usize;
    let mut output = Vec::with_capacity(output_len);
    for i in 0..output_len {
        let position = i as f64 * ratio;
        let index = position.floor() as usize;
        let fraction = (position - position.floor()) as f32;
        let a = input[index.min(input.len() - 1)];
        let b = input[(index + 1).min(input.len() - 1)];
        output.push(a + (b - a) * fraction);
    }
    output
}

fn uuid_v4_string() -> String {
    // Minimal v4 UUID without pulling uuid into this crate.
    let mut bytes = [0u8; 16];
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let seed = now.as_nanos() as u64 ^ (std::process::id() as u64) << 32;
    let mut state = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
    for chunk in bytes.chunks_mut(8) {
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let rand_bytes = state.to_le_bytes();
        let len = chunk.len();
        chunk.copy_from_slice(&rand_bytes[..len]);
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn linear_resampling_halves_and_preserves_length_ratio() {
        let input: Vec<f32> = (0..48_000).map(|i| (i as f32 / 48_000.0).sin()).collect();
        let output = resample_linear(&input, 48_000, 24_000);
        assert_eq!(output.len(), 24_000);
        let same = resample_linear(&input, 48_000, 48_000);
        assert_eq!(same.len(), input.len());
    }

    #[test]
    fn resampling_empty_input_is_empty() {
        assert!(resample_linear(&[], 48_000, 24_000).is_empty());
    }

    #[test]
    fn uuid_shape_is_valid() {
        let id = uuid_v4_string();
        assert_eq!(id.len(), 36);
        assert_eq!(id.as_bytes()[14], b'4');
    }
}
