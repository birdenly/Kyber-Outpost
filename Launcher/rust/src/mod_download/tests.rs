use super::downloader::ZipDownloader;
use std::io::{Cursor, Write};
use tokio::{io::{AsyncReadExt, AsyncWriteExt}, net::TcpListener};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn mod_zip_can_be_listed_read_and_downloaded_without_maxima() {
    let mut archive = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let stored = zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
    let deflated = zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
    archive.start_file("stored.fbmod", stored).unwrap();
    archive.write_all(b"stored mod content").unwrap();
    archive.start_file("deflated.fbmod", deflated).unwrap();
    archive.write_all(b"compressed mod content").unwrap();
    archive.start_file("padding.bin", stored).unwrap();
    archive.write_all(&vec![0x35; 16384]).unwrap();
    let bytes = std::sync::Arc::new(archive.finish().unwrap().into_inner());
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/mods.zip", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        loop {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut request = Vec::new();
            loop {
                let mut chunk = [0; 1024];
                let size = stream.read(&mut chunk).await.unwrap();
                if size == 0 { break; }
                request.extend_from_slice(&chunk[..size]);
                if request.ends_with(b"\r\n\r\n") { break; }
            }
            let request = String::from_utf8_lossy(&request).to_lowercase();
            if request.starts_with("head ") {
                stream.write_all(format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", bytes.len()).as_bytes()).await.unwrap();
            } else {
                let range = request.lines().find_map(|line| line.strip_prefix("range: bytes=")).unwrap();
                let (start, end) = range.split_once('-').unwrap();
                let start: usize = start.parse().unwrap();
                let end = end.parse::<usize>().unwrap().min(bytes.len() - 1);
                let body = &bytes[start..=end];
                stream.write_all(format!("HTTP/1.1 206 Partial Content\r\nContent-Length: {}\r\nContent-Range: bytes {}-{}/{}\r\nConnection: close\r\n\r\n", body.len(), start, end, bytes.len()).as_bytes()).await.unwrap();
                stream.write_all(body).await.unwrap();
            }
        }
    });
    let id = format!("outpost-mod-test-{}", std::process::id());
    let output = std::env::temp_dir().join(&id);
    tokio::fs::create_dir_all(&output).await.unwrap();
    let downloader = ZipDownloader::new(&id, &url, &output).await.unwrap();
    assert_eq!(downloader.manifest().entries().len(), 3);
    for (name, expected) in [("stored.fbmod", b"stored mod content".as_slice()), ("deflated.fbmod", b"compressed mod content".as_slice())] {
        let entry = downloader.manifest().entries().iter().find(|entry| entry.name() == name).unwrap();
        assert_eq!(downloader.read_zip_entry_bytes(entry, expected.len() as u64).await.unwrap().as_ref(), expected);
        downloader.download_single_file(entry, None).await.unwrap();
        assert_eq!(tokio::fs::read(output.join(name)).await.unwrap(), expected);
    }
    server.abort();
    tokio::fs::remove_dir_all(output).await.unwrap();
}
