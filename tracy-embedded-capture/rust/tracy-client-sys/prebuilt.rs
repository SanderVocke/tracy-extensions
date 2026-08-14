use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

pub const NATIVE_PROFILE: &str = "embedded_capture,enable,on_demand,manual_lifetime,delayed_init,timer_fallback,no_system_tracing,no_context_switch,no_sampling,no_code_transfer,no_broadcast,no_callstack_inlines,no_crash_handler,no_verify,no_debuginfod,no_demangle,no_fibers,no_flush_on_exit,no_only_localhost,no_only_ipv4,no_build_testing";

#[derive(Debug)]
pub struct Bundle {
    pub lib_dir: PathBuf,
    pub embedded_archive: String,
    pub capstone_archive: String,
    pub zstd_archive: String,
}

fn parse_manifest(text: &str) -> Result<BTreeMap<String, String>, String> {
    let mut values = BTreeMap::new();
    for (index, line) in text.lines().enumerate() {
        let (key, value) = line
            .split_once('=')
            .ok_or_else(|| format!("malformed manifest line {}", index + 1))?;
        if key.is_empty()
            || !key
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || b"_./-".contains(&byte))
        {
            return Err(format!("invalid manifest key on line {}: {key}", index + 1));
        }
        if values.insert(key.to_owned(), value.to_owned()).is_some() {
            return Err(format!("duplicate manifest key: {key}"));
        }
    }
    Ok(values)
}

fn require<'a>(
    values: &'a BTreeMap<String, String>,
    key: &str,
    expected: Option<&str>,
) -> Result<&'a str, String> {
    let value = values
        .get(key)
        .ok_or_else(|| format!("manifest is missing {key}"))?;
    if let Some(expected) = expected {
        if value != expected {
            return Err(format!(
                "manifest {key} is {value:?}, expected {expected:?}"
            ));
        }
    } else if value.is_empty() {
        return Err(format!("manifest {key} must not be empty"));
    }
    Ok(value)
}

fn collect_files(root: &Path, current: &Path, output: &mut BTreeSet<String>) -> Result<(), String> {
    for entry in fs::read_dir(current)
        .map_err(|error| format!("cannot read {}: {error}", current.display()))?
    {
        let entry = entry.map_err(|error| format!("cannot read bundle entry: {error}"))?;
        let file_type = entry
            .file_type()
            .map_err(|error| format!("cannot inspect {}: {error}", entry.path().display()))?;
        if file_type.is_symlink() {
            return Err(format!(
                "bundle payload must not be a symlink: {}",
                entry.path().display()
            ));
        }
        if file_type.is_dir() {
            collect_files(root, &entry.path(), output)?;
        } else if file_type.is_file() {
            let relative = entry
                .path()
                .strip_prefix(root)
                .map_err(|error| format!("invalid bundle path: {error}"))?
                .to_string_lossy()
                .replace('\\', "/");
            output.insert(relative);
        } else {
            return Err(format!(
                "unsupported bundle payload type: {}",
                entry.path().display()
            ));
        }
    }
    Ok(())
}

fn safe_archive_name(value: &str, field: &str) -> Result<String, String> {
    if value.is_empty()
        || value.starts_with('.')
        || value.contains('/')
        || value.contains('\\')
        || value.contains("..")
    {
        return Err(format!(
            "manifest {field} has unsafe archive name: {value:?}"
        ));
    }
    Ok(value.to_owned())
}

pub fn validate(
    root: &Path,
    target: &str,
    target_arch: &str,
    target_os: &str,
    crt_static: bool,
) -> Result<Bundle, String> {
    if !root.is_dir() {
        return Err(format!(
            "bundle directory does not exist: {}",
            root.display()
        ));
    }
    let manifest_path = root.join("manifest.txt");
    let text = fs::read_to_string(&manifest_path)
        .map_err(|error| format!("cannot read {}: {error}", manifest_path.display()))?;
    let values = parse_manifest(&text)?;

    require(&values, "bundle_format_version", Some("1"))?;
    require(&values, "tracy_extensions_version", Some("0.5.0"))?;
    require(&values, "tracy_version", Some("0.13.1"))?;
    require(&values, "tracy_protocol", Some("76"))?;
    require(&values, "target_triple", Some(target))?;
    let expected_arch = match target_arch {
        "x86_64" => "x86_64",
        "aarch64" => "aarch64",
        other => return Err(format!("unsupported prebuilt target architecture: {other}")),
    };
    require(&values, "architecture", Some(expected_arch))?;
    require(&values, "platform", None)?;
    require(&values, "build_profile", Some("release"))?;
    require(
        &values,
        "native_feature_profile",
        Some("embedded-capture-v1"),
    )?;
    require(&values, "native_definitions", Some(NATIVE_PROFILE))?;
    require(&values, "pic_policy", Some("enabled"))?;
    match target_os {
        "linux" => {
            require(&values, "runtime_abi", Some("gnu-glibc"))?;
            require(&values, "deployment_baseline", Some("ubuntu-24.04-glibc"))?;
        }
        "macos" => {
            require(&values, "runtime_abi", Some("apple-clang-libc++"))?;
            require(&values, "deployment_baseline", Some("macos-12.0"))?;
        }
        "windows" => {
            if crt_static {
                return Err("the embedded-capture-v1 bundle requires the dynamic MSVC CRT, but target-feature=crt-static is active".to_owned());
            }
            require(&values, "runtime_abi", Some("msvc-dynamic"))?;
            require(&values, "deployment_baseline", Some("windows-10"))?;
        }
        other => return Err(format!("unsupported prebuilt target OS: {other}")),
    }
    require(&values, "compiler", None)?;
    let commit = require(&values, "source_commit", None)?;
    if commit.len() != 40 || !commit.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err("manifest source_commit is not a full Git SHA".to_owned());
    }

    let embedded_archive = safe_archive_name(
        require(&values, "embedded_archive", None)?,
        "embedded_archive",
    )?;
    let capstone_archive = safe_archive_name(
        require(&values, "capstone_archive", None)?,
        "capstone_archive",
    )?;
    let zstd_archive = safe_archive_name(require(&values, "zstd_archive", None)?, "zstd_archive")?;
    let expected_archives = if target_os == "windows" {
        (
            "tracy_embedded_capture_native.lib",
            "capstone.lib",
            "zstd_static.lib",
        )
    } else {
        (
            "libtracy_embedded_capture_native.a",
            "libcapstone.a",
            "libzstd.a",
        )
    };
    if (
        embedded_archive.as_str(),
        capstone_archive.as_str(),
        zstd_archive.as_str(),
    ) != expected_archives
    {
        return Err(format!(
            "manifest archive names do not match the {target_os} bundle ABI"
        ));
    }

    let expected: BTreeSet<String> = require(&values, "expected_files", None)?
        .split(',')
        .map(str::to_owned)
        .collect();
    if expected.len() != 13 {
        return Err(format!(
            "manifest must name exactly thirteen payload files, found {}",
            expected.len()
        ));
    }
    let required_files = [
        "include/tracy_embedded_capture/embedded_capture.h".to_owned(),
        format!("lib/{embedded_archive}"),
        format!("lib/{capstone_archive}"),
        format!("lib/{zstd_archive}"),
        "licenses/COPYING-ZSTD".to_owned(),
        "licenses/LICENSE-APACHE".to_owned(),
        "licenses/LICENSE-CAPSTONE".to_owned(),
        "licenses/LICENSE-CAPSTONE-BSD-3-CLAUSE".to_owned(),
        "licenses/LICENSE-CAPSTONE-LLVM".to_owned(),
        "licenses/LICENSE-MIT".to_owned(),
        "licenses/LICENSE-TRACY".to_owned(),
        "licenses/LICENSE-ZSTD".to_owned(),
        "licenses/PROVENANCE.txt".to_owned(),
    ];
    let required_set: BTreeSet<String> = required_files.into_iter().collect();
    if expected != required_set {
        return Err(format!(
            "manifest payload inventory is invalid: {expected:?}"
        ));
    }

    let mut actual = BTreeSet::new();
    collect_files(root, root, &mut actual)?;
    let mut expected_with_manifest = expected.clone();
    expected_with_manifest.insert("manifest.txt".to_owned());
    if actual != expected_with_manifest {
        return Err(format!(
            "bundle file inventory mismatch; actual={actual:?}, expected={expected_with_manifest:?}"
        ));
    }

    for relative in &expected {
        let path = root.join(relative);
        let metadata = fs::metadata(&path)
            .map_err(|error| format!("cannot inspect {}: {error}", path.display()))?;
        if metadata.len() == 0 {
            return Err(format!("bundle payload is empty: {relative}"));
        }
        let expected_digest = require(&values, &format!("sha256.{relative}"), None)?;
        if expected_digest.len() != 64
            || !expected_digest.bytes().all(|byte| byte.is_ascii_hexdigit())
        {
            return Err(format!("invalid SHA-256 field for {relative}"));
        }
        let bytes =
            fs::read(&path).map_err(|error| format!("cannot read {}: {error}", path.display()))?;
        let actual_digest = sha256_hex(&bytes);
        if !actual_digest.eq_ignore_ascii_case(expected_digest) {
            return Err(format!(
                "SHA-256 mismatch for {relative}: got {actual_digest}, expected {expected_digest}"
            ));
        }
    }
    if values.len() != 19 + expected.len() {
        return Err(format!(
            "manifest has unexpected fields: found {}, expected {}",
            values.len(),
            19 + expected.len()
        ));
    }

    Ok(Bundle {
        lib_dir: root.join("lib"),
        embedded_archive,
        capstone_archive,
        zstd_archive,
    })
}

fn sha256_hex(input: &[u8]) -> String {
    const INITIAL: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let bit_len = (input.len() as u64).wrapping_mul(8);
    let mut padded = input.to_vec();
    padded.push(0x80);
    while padded.len() % 64 != 56 {
        padded.push(0);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());
    let mut hash = INITIAL;
    for chunk in padded.chunks_exact(64) {
        let mut words = [0u32; 64];
        for (index, bytes) in chunk.chunks_exact(4).enumerate() {
            words[index] = u32::from_be_bytes(bytes.try_into().unwrap());
        }
        for index in 16..64 {
            let s0 = words[index - 15].rotate_right(7)
                ^ words[index - 15].rotate_right(18)
                ^ (words[index - 15] >> 3);
            let s1 = words[index - 2].rotate_right(17)
                ^ words[index - 2].rotate_right(19)
                ^ (words[index - 2] >> 10);
            words[index] = words[index - 16]
                .wrapping_add(s0)
                .wrapping_add(words[index - 7])
                .wrapping_add(s1);
        }
        let mut work = hash;
        for index in 0..64 {
            let sigma1 =
                work[4].rotate_right(6) ^ work[4].rotate_right(11) ^ work[4].rotate_right(25);
            let choose = (work[4] & work[5]) ^ (!work[4] & work[6]);
            let temp1 = work[7]
                .wrapping_add(sigma1)
                .wrapping_add(choose)
                .wrapping_add(K[index])
                .wrapping_add(words[index]);
            let sigma0 =
                work[0].rotate_right(2) ^ work[0].rotate_right(13) ^ work[0].rotate_right(22);
            let majority = (work[0] & work[1]) ^ (work[0] & work[2]) ^ (work[1] & work[2]);
            let temp2 = sigma0.wrapping_add(majority);
            work = [
                temp1.wrapping_add(temp2),
                work[0],
                work[1],
                work[2],
                work[3].wrapping_add(temp1),
                work[4],
                work[5],
                work[6],
            ];
        }
        for index in 0..8 {
            hash[index] = hash[index].wrapping_add(work[index]);
        }
    }
    hash.iter().map(|word| format!("{word:08x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_known_vector() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn rejects_duplicate_manifest_key() {
        assert!(parse_manifest("a=1\na=2\n")
            .unwrap_err()
            .contains("duplicate"));
    }

    #[test]
    fn rejects_unsafe_archive_name() {
        assert!(safe_archive_name("../bad.a", "archive").is_err());
    }
}
