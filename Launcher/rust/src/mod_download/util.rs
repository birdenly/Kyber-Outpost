use std::{env, io, path::{Path, PathBuf}};

pub fn cache_directory() -> io::Result<PathBuf> {
    let root = env::var_os("LOCALAPPDATA").map(PathBuf::from)
        .unwrap_or_else(env::temp_dir).join("KyberOutpost/cache");
    std::fs::create_dir_all(&root)?;
    Ok(root)
}

pub trait SafeParent { fn safe_parent(&self) -> io::Result<&Path>; }
impl SafeParent for PathBuf {
    fn safe_parent(&self) -> io::Result<&Path> {
        self.parent().ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Download path has no parent"))
    }
}
