//! Standalone ZIP mod downloads extracted from Maxima (GPL-3.0).
//! No account, library, content-service or game-download manager is included.
pub mod downloader;
pub mod zip;
mod zlib;
mod error;
mod util;
#[cfg(test)]
mod tests;
