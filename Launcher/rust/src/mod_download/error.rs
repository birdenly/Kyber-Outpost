use super::{downloader::DownloadError, zip::{ZipError, CompressionType}};
use std::path::PathBuf;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum DownloaderError {
    #[error(transparent)] Zip(#[from] ZipError),
    #[error(transparent)] Request(#[from] reqwest::Error),
    #[error(transparent)] Io(#[from] std::io::Error),
    #[error(transparent)] Download(#[from] DownloadError),
    #[error("path `{0}` is not absolute")] PathNotAbsolute(PathBuf),
    #[error("failed to download range: {0}")] Http(reqwest::StatusCode),
    #[error("requested length ({requested}) exceeds entry size ({entry})")] EntrySize { requested: u64, entry: usize },
    #[error("unsupported compression type `{0:?}`")] CompressionType(CompressionType),
}
