import type { NextConfig } from "next";

// Static export for GitHub Pages under /vibecompose subpath.
// If a custom root domain is adopted later (post brand clearance),
// clear BASE_PATH so basePath/assetPrefix become empty.
const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "/vibecompose";

const nextConfig: NextConfig = {
  output: "export",
  basePath: BASE_PATH,
  assetPrefix: BASE_PATH,
  trailingSlash: true,
  images: {
    unoptimized: true, // GitHub Pages has no Image Optimization server
  },
  env: {
    NEXT_PUBLIC_BASE_PATH: BASE_PATH,
  },
};

export default nextConfig;
