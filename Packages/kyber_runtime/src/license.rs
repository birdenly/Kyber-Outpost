// Local DLF format support adapted from ArmchairDevelopers/Maxima (GPL-3.0).
// Reads an existing activation only; no token creation or online renewal.
use std::{env, fs, path::Path};
use aes::cipher::{block_padding::Pkcs7, BlockDecryptMut, KeyIvInit};
use anyhow::{ensure, Context, Result};
use serde::Deserialize;

const KEY: [u8; 16] = [65, 50, 114, 45, 208, 130, 239, 176, 220, 100, 87, 197, 118, 104, 202, 9];

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct LocalLicense {
    pub content_id: String,
    pub user_id: String,
    pub game_token: String,
}

fn decode(bytes: &[u8]) -> Result<LocalLicense> {
    ensure!(bytes.len() > 65, "The local activation file is incomplete");
    let plain = cbc::Decryptor::<aes::Aes128>::new(&KEY.into(), &[0u8; 16].into())
        .decrypt_padded_vec_mut::<Pkcs7>(&bytes[65..])
        .map_err(|_| anyhow::anyhow!("The local activation file could not be decoded"))?;
    // Parsing errors must never include the XML or the private token.
    let license: LocalLicense = quick_xml::de::from_reader(plain.as_slice())
        .map_err(|_| anyhow::anyhow!("The local activation file has an invalid format"))?;
    ensure!(license.content_id == super::CONTENT_ID, "The local activation belongs to another game");
    ensure!(!license.game_token.is_empty() && license.game_token.bytes().all(|b| b.is_ascii_alphanumeric() || b"-_/+=".contains(&b)), "The local Denuvo token is missing or malformed");
    Ok(license)
}

fn load_from(directory: &Path) -> Result<LocalLicense> {
    let direct = directory.join(format!("{}.dlf", super::CONTENT_ID));
    let cached = directory.join(format!("{}_cached.dlf", super::CONTENT_ID));
    let path = if direct.is_file() { direct } else { cached };
    decode(&fs::read(path).context("A local Denuvo activation is required. Start the original game through its official store on this computer, then return to Outpost.")?)
}

pub fn load_local_license() -> Result<LocalLicense> {
    let program_data = env::var_os("ProgramData").unwrap_or_else(|| "C:/ProgramData".into());
    load_from(&Path::new(&program_data).join("Electronic Arts/EA Services/License"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use aes::cipher::BlockEncryptMut;
    #[test]
    fn reads_existing_dlf_and_rejects_corruption_without_disclosing_tokens() {
        let xml = b"<License><ContentId>1035052</ContentId><UserId>123</UserId><GameToken>private-test-token</GameToken></License>";
        let mut blob = vec![0u8; 65];
        blob.extend(cbc::Encryptor::<aes::Aes128>::new(&KEY.into(), &[0u8; 16].into()).encrypt_padded_vec_mut::<Pkcs7>(xml));
        let license = decode(&blob).unwrap();
        assert_eq!(license.user_id, "123");
        assert_eq!(license.game_token, "private-test-token");
        assert!(decode(&blob[..65]).is_err());
        blob[65] ^= 0x7f;
        let error = decode(&blob).err().unwrap().to_string();
        assert!(!error.contains("private-test-token"));
    }
}
