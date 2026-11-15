//! Edit quoted KeyValues without discarding user options or comments.
use anyhow::{bail, ensure, Context, Result};
use sha1::{Digest, Sha1};
use std::{
    fs,
    io::{Read, Write},
    ops::Range,
    path::Path,
};

struct Entry {
    key: String,
    value: Value,
}
enum Value {
    Text(String, Range<usize>),
    Group(Vec<Entry>, usize),
}

struct Parser<'a> {
    text: &'a str,
    at: usize,
}
impl Parser<'_> {
    fn whitespace(&mut self) -> Result<()> {
        loop {
            while self.at < self.text.len() && self.text.as_bytes()[self.at].is_ascii_whitespace() {
                self.at += 1;
            }
            if self.text[self.at..].starts_with("//") {
                self.at += self.text[self.at..].find('\n').unwrap_or(self.text.len() - self.at);
            } else if self.text[self.at..].starts_with("/*") {
                self.at += 2;
                self.at += self.text[self.at..].find("*/").context("Unclosed configuration comment")? + 2;
            } else {
                return Ok(());
            }
        }
    }
    fn quoted(&mut self) -> Result<(String, Range<usize>)> {
        self.whitespace()?;
        let start = self.at;
        ensure!(self.text.as_bytes().get(self.at) == Some(&b'"'), "Expected a quoted configuration key or value");
        self.at += 1;
        let mut value = String::new();
        while let Some(c) = self.text[self.at..].chars().next() {
            self.at += c.len_utf8();
            if c == '"' {
                return Ok((value, start..self.at));
            }
            if c == '\\' {
                // Keep ordinary Windows path separators; decode escaped quotes/backslashes.
                if let Some(next @ ('"' | '\\')) = self.text[self.at..].chars().next() {
                    self.at += next.len_utf8();
                    value.push(next);
                    continue;
                }
            }
            value.push(c);
        }
        bail!("Unclosed configuration value")
    }
    fn group(&mut self) -> Result<Value> {
        self.whitespace()?;
        ensure!(self.text.as_bytes().get(self.at) == Some(&b'{'), "Expected a configuration section");
        self.at += 1;
        let mut entries = Vec::<Entry>::new();
        loop {
            self.whitespace()?;
            if self.text.as_bytes().get(self.at) == Some(&b'}') {
                let end = self.at;
                self.at += 1;
                return Ok(Value::Group(entries, end));
            }
            let (key, _) = self.quoted()?;
            ensure!(!entries.iter().any(|e| e.key == key), "Duplicate configuration key: {key}");
            self.whitespace()?;
            let value = if self.text.as_bytes().get(self.at) == Some(&b'{') {
                self.group()?
            } else {
                let (text, span) = self.quoted()?;
                Value::Text(text, span)
            };
            entries.push(Entry { key, value });
        }
    }
}

fn parse(text: &str) -> Result<Value> {
    let mut parser = Parser {
        text,
        at: if text.starts_with('\u{feff}') { 3 } else { 0 },
    };
    ensure!(parser.quoted()?.0 == "Config2", "Expected the Config2 configuration root");
    let root = parser.group()?;
    parser.whitespace()?;
    ensure!(parser.at == text.len(), "Unexpected content after configuration root");
    Ok(root)
}

fn quote(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn locate<'a>(mut root: &'a Value, path: &[&str]) -> Result<Option<&'a Value>> {
    for key in path {
        let Value::Group(entries, _) = root else {
            bail!("Expected a configuration section");
        };
        match entries.iter().find(|e| e.key == *key) {
            Some(entry) => root = &entry.value,
            None => return Ok(None),
        }
    }
    Ok(Some(root))
}

enum Update {
    Missing,
    Always,
}

struct Edit {
    span: Range<usize>,
    replacement: String,
}

/// Parse once, then apply edits from the end to retain original source positions.
struct Configuration {
    source: String,
    root: Value,
    edits: Vec<Edit>,
    new_sections: String,
}

impl Configuration {
    fn read(source: String) -> Result<Self> {
        let root = parse(&source).context("Invalid anadius.cfg; the file was left unchanged")?;
        Ok(Self {
            source,
            root,
            edits: Vec::new(),
            new_sections: String::new(),
        })
    }

    fn value(&self, section: &str, key: &str) -> Result<Option<&str>> {
        match locate(&self.root, &[section, key])? {
            Some(Value::Text(value, _)) => Ok(Some(value)),
            Some(_) => bail!("Expected a value for {section}/{key}"),
            None => Ok(None),
        }
    }

    fn newline(&self) -> &str {
        if self.source.contains("\r\n") { "\r\n" } else { "\n" }
    }

    fn update_section(&mut self, section: &str, settings: &[(&str, String, Update)]) -> Result<()> {
        let existing = locate(&self.root, &[section])?;
        let (entries, close) = match existing {
            Some(Value::Group(entries, close)) => (entries.as_slice(), Some(*close)),
            Some(_) => bail!("Expected a section for {section}"),
            None => (&[][..], None),
        };
        let mut additions = String::new();
        for (key, value, update) in settings {
            if let Some(entry) = entries.iter().find(|entry| entry.key == *key) {
                let Value::Text(current, span) = &entry.value else {
                    bail!("Expected a value for {section}/{key}");
                };
                let replace = matches!(update, Update::Always) || current.is_empty();
                if replace && current != value {
                    self.edits.push(Edit {
                        span: span.clone(),
                        replacement: quote(value),
                    });
                }
            } else {
                additions.push_str(&format!(
                    "        {} {}{}", quote(key), quote(value), self.newline(),
                ));
            }
        }
        if additions.is_empty() {
            return Ok(());
        }
        if let Some(close) = close {
            self.insert_before_close(close, 1, additions);
        } else {
            let newline = self.newline();
            let section = format!("    {}{newline}    {{{newline}{additions}    }}{newline}", quote(section));
            self.new_sections.push_str(&section);
        }
        Ok(())
    }

    fn insert_before_close(&mut self, close: usize, depth: usize, mut block: String) {
        let line_start = self.source[..close].rfind('\n').map_or(0, |at| at + 1);
        let on_own_line = self.source[line_start..close].chars().all(char::is_whitespace);
        let at = if on_own_line { line_start } else { close };
        if !on_own_line {
            block = format!("{}{}{}", self.newline(), block, "    ".repeat(depth));
        }
        self.edits.push(Edit {
            span: at..at,
            replacement: block,
        });
    }

    fn has_changes(&self) -> bool {
        !self.edits.is_empty() || !self.new_sections.is_empty()
    }

    fn finish(mut self) -> String {
        if let Value::Group(_, close) = self.root {
            if !self.new_sections.is_empty() {
                let sections = std::mem::take(&mut self.new_sections);
                self.insert_before_close(close, 0, sections);
            }
        }
        self.edits.sort_by_key(|edit| std::cmp::Reverse(edit.span.start));
        for edit in self.edits {
            self.source.replace_range(edit.span, &edit.replacement);
        }
        self.source
    }
}

fn sha1_file(path: &Path) -> Result<String> {
    let mut file = fs::File::open(path).with_context(|| format!("Could not read {} to calculate its SHA-1", path.display()))?;
    let mut hash = Sha1::new();
    let mut buffer = [0; 65536];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hash.update(&buffer[..count]);
    }
    Ok(format!("{:x}", hash.finalize()))
}

pub(crate) fn prepare(
    path: &Path,
    module: &Path,
    token: &str,
    profile: &super::LocalProfile,
) -> Result<()> {
    let directory = path.parent().context("Game executable has no directory")?;
    ensure!(directory.join("anadius64.dll").is_file(), "The offline installation at {} is incomplete: anadius64.dll is missing.", directory.display());
    ensure!(module.is_absolute() && module.is_file(), "The local Kyber module path is invalid");
    ensure!(!profile.name.is_empty() && profile.name.chars().count() <= 16 &&
        !profile.name.chars().any(|c| c == '"' || c == '\\' || c.is_control()),
        "Choose a nickname with 1 to 16 characters, without quotes, backslashes or control characters.");
    ensure!(!token.chars().any(char::is_control), "Invalid local activation token");
    let user_id = profile.id.parse::<u64>().context("The local player ID is invalid")?;
    let config_path = directory.join("anadius.cfg");
    let text = match fs::read_to_string(&config_path) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => "\"Config2\"\n{\n}\n".into(),
        Err(error) => return Err(error).context("Could not read anadius.cfg"),
    };
    let mut config = Configuration::read(text)?;
    let dll = config.value("Game", "DenuvoDllName")?
        .filter(|name| !name.is_empty()).unwrap_or("dbdata.dll").to_owned();
    ensure!(!dll.contains(['/', '\\', ':']) && dll != "." && dll != "..", "DenuvoDllName must be a filename beside the game executable");
    let exe_hash = sha1_file(path)?;
    let dll_hash = sha1_file(&directory.join(&dll))?;
    use Update::{Always, Missing};
    config.update_section("Game", &[
        ("Name", "STAR WARS Battlefront II".into(), Missing),
        ("ContentId", super::CONTENT_ID.into(), Missing),
        ("Language", "en_US".into(), Missing),
        ("DenuvoDllName", dll, Missing),
        ("DenuvoExeHash", exe_hash, Always),
        ("DenuvoDllHash", dll_hash, Always),
        ("DenuvoToken", token.to_owned(), Always),
    ])?;
    config.update_section("User", &[
        ("Username", profile.name.clone(), Always),
        ("UserId", user_id.to_string(), Always),
        ("PersonaId", ((user_id & 0x3fffffff) | 0x40000000).to_string(), Always),
        ("UseLastOnlineProfile", "false".into(), Missing),
        ("IsSubscriber", "false".into(), Missing),
    ])?;
    config.update_section("Emulator", &[
        ("ServerPort", "0".into(), Missing),
        ("PretendConnected", "false".into(), Missing),
        ("FakeAuth", "false".into(), Missing),
        ("LoadExtraDLLsFromMain", module.to_string_lossy().replace('\\', "/"), Always),
    ])?;
    if !config.has_changes() {
        return Ok(());
    }
    let text = config.finish();
    // Persist atomically so an interrupted write cannot truncate the user's config.
    let mut temporary = tempfile::NamedTempFile::new_in(directory).context("Could not create configuration in the game folder; check Modify permission")?;
    temporary.write_all(text.as_bytes())?;
    temporary.as_file().sync_all()?;
    temporary.persist(&config_path).map_err(|_| anyhow::anyhow!("Could not replace anadius.cfg; check Modify permission for the file and game folder"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn value(text: &str, section: &str, key: &str) -> String {
        match locate(&parse(text).unwrap(), &[section, key]).unwrap().unwrap() {
            Value::Text(value, _) => value.clone(),
            _ => panic!("Expected a scalar"),
        }
    }

    #[test]
    fn creates_and_refreshes_one_configuration() {
        let directory = tempfile::tempdir().unwrap();
        let exe = directory.path().join("starwarsbattlefrontii.exe");
        let dll = directory.path().join("dbdata.dll");
        let module = directory.path().join("Kyber.dll");
        for file in [&exe, &dll, &module, &directory.path().join("anadius64.dll")] { fs::write(file, "abc").unwrap(); }
        let profile = super::super::LocalProfile { id: "4503599627370497".into(), name: "Player Two".into() };
        prepare(&exe, &module, "test-token", &profile).unwrap();
        let config = directory.path().join("anadius.cfg");
        let first = fs::read_to_string(&config).unwrap();
        assert_eq!(value(&first, "Game", "DenuvoExeHash"), "a9993e364706816aba3e25717850c26c9cd0d89d");
        assert_eq!(value(&first, "Game", "DenuvoDllHash"), value(&first, "Game", "DenuvoExeHash"));
        assert_eq!(value(&first, "User", "Username"), "Player Two");
        assert_eq!(value(&first, "User", "PersonaId"), "1073741825");
        assert_eq!(value(&first, "Game", "ContentId"), super::super::CONTENT_ID);
        // Keep user settings and comments while refreshing managed values.
        let custom = first.replace("\"en_US\"", "\"pt_BR\"");
        let commented = format!("\u{feff}// keep this comment\r\n{}", custom.replace('\n', "\r\n"));
        fs::write(&config, commented).unwrap();
        fs::write(&exe, "changed executable").unwrap();
        prepare(&exe, &module, "new-test-token", &profile).unwrap();
        let second = fs::read_to_string(&config).unwrap();
        assert!(second.starts_with("\u{feff}// keep this comment\r\n"));
        assert_eq!(value(&second, "Game", "Language"), "pt_BR");
        assert_eq!(value(&second, "Game", "DenuvoExeHash"), sha1_file(&exe).unwrap());
        assert_eq!(value(&second, "Game", "DenuvoToken"), "new-test-token");
        prepare(&exe, &module, "new-test-token", &profile).unwrap();
        assert_eq!(second, fs::read_to_string(&config).unwrap());
        // Reject an invalid name without changing configuration or leaking activation.
        let bad = super::super::LocalProfile { id: profile.id.clone(), name: "bad\"name".into() };
        let error = prepare(&exe, &module, "private-test-token", &bad).unwrap_err().to_string();
        assert!(!error.contains("private-test-token"));
        assert_eq!(second, fs::read_to_string(&config).unwrap());
        // Malformed files are never silently overwritten.
        fs::write(&config, "\"Config2\" { \"Game\" { ").unwrap();
        assert!(prepare(&exe, &module, "test-token", &profile).is_err());
        assert_eq!(fs::read_to_string(config).unwrap(), "\"Config2\" { \"Game\" { ");
    }

    #[test]
    fn edits_preserve_unknown_values_and_reject_ambiguous_structure() {
        let text = "\"Config2\" { /* keep */ \"Game\" { \"Language\" \"\" } \"Other\" { \"Path\" \"C:\\games\\mod\" } }".to_owned();
        let mut config = Configuration::read(text).unwrap();
        config.update_section("Game", &[("Language", "en_US".into(), Update::Missing)]).unwrap();
        config.update_section("Other", &[("Escaped", "quote: \" and backslash: \\".into(), Update::Always)]).unwrap();
        let text = config.finish();
        assert_eq!(value(&text, "Game", "Language"), "en_US");
        assert_eq!(value(&text, "Other", "Path"), "C:\\games\\mod");
        assert_eq!(value(&text, "Other", "Escaped"), "quote: \" and backslash: \\");
        assert!(text.contains("/* keep */"));
        for bad in ["\"Config2\" { \"Game\" {} \"Game\" {} }", "\"Config2\" { /* unclosed", "\"Config2\" {} trailing"] {
            assert!(parse(bad).is_err());
        }
    }
}
