use flate2::read::MultiGzDecoder;
use quick_xml::{events::Event, Reader};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{self, BufRead, BufReader, Read},
    path::Path,
};
use tauri::Window;
use zip::ZipArchive;

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum SetupSelectionKind {
    Workspace,
    Playlist,
    Guide,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum SetupSelectionOutcome {
    Selected,
    Cancelled,
    Rejected,
    Unavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum SelectionStatus {
    Selected,
    NotSelected,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ValidationStatus {
    NotChecked,
    Checking,
    ReadyToInspect,
    NeedsAttention,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum PickerReasonCode {
    PickerUnavailable,
    PermissionDenied,
    WrongKind,
    Unknown,
    NotFound,
    NotReadable,
    CheckUnavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum PlaylistContentStatus {
    NotChecked,
    Checking,
    Checked,
    NeedsAttention,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum PlaylistContentReasonCode {
    MissingHeader,
    EmptyPlaylist,
    IncompleteEntry,
    OrphanStreamLine,
    InvalidEncoding,
    TooLarge,
    Unreadable,
    CheckUnavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum GuideContentStatus {
    NotChecked,
    Checking,
    Checked,
    NeedsAttention,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum GuideContentReasonCode {
    MissingRoot,
    EmptyGuide,
    IncompleteChannel,
    IncompleteProgramme,
    InvalidEncoding,
    TooLarge,
    UnsupportedFormat,
    MalformedXml,
    Unreadable,
    CheckUnavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GuideContentSummary {
    pub content_status: GuideContentStatus,
    pub channel_count: Option<u64>,
    pub programme_count: Option<u64>,
    pub reason_code: Option<GuideContentReasonCode>,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaylistContentSummary {
    pub content_status: PlaylistContentStatus,
    pub entry_count: Option<u64>,
    pub reason_code: Option<PlaylistContentReasonCode>,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SetupSelectionResult {
    pub kind: SetupSelectionKind,
    pub outcome: SetupSelectionOutcome,
    pub selection_status: SelectionStatus,
    pub validation_status: ValidationStatus,
    pub reason_code: Option<PickerReasonCode>,
    #[serde(rename = "playlistContent", skip_serializing_if = "Option::is_none")]
    pub playlist_content: Option<PlaylistContentSummary>,
    #[serde(rename = "guideContent", skip_serializing_if = "Option::is_none")]
    pub guide_content: Option<GuideContentSummary>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum PickerSelectionKind {
    Workspace,
    File,
}

impl PickerSelectionKind {
    fn matches(self, kind: SetupSelectionKind) -> bool {
        matches!(
            (kind, self),
            (
                SetupSelectionKind::Workspace,
                PickerSelectionKind::Workspace
            ) | (SetupSelectionKind::Playlist, PickerSelectionKind::File)
                | (SetupSelectionKind::Guide, PickerSelectionKind::File)
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum PreParseReason {
    NotFound,
    WrongKind,
    NotReadable,
    CheckUnavailable,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum PreParseCheck {
    ReadyToInspect,
    NeedsAttention(PreParseReason),
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct PickerSelection {
    kind: PickerSelectionKind,
    pre_parse_check: PreParseCheck,
    playlist_content: Option<PlaylistContentSummary>,
    guide_content: Option<GuideContentSummary>,
}

// Native rfd returns cancellation as `None`; fake adapters cover bounded error mapping.
#[allow(dead_code)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum PickerError {
    Unavailable,
    PermissionDenied,
    Unknown,
}

trait PickerAdapter: Send + Sync {
    fn pick(&self, kind: SetupSelectionKind) -> Result<Option<PickerSelection>, PickerError>;
}

struct NativePicker<'a> {
    window: &'a Window,
}

impl PickerAdapter for NativePicker<'_> {
    fn pick(&self, kind: SetupSelectionKind) -> Result<Option<PickerSelection>, PickerError> {
        let selection = match kind {
            SetupSelectionKind::Workspace => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose workspace")
                .pick_folder()
                .map(|path| PickerSelection {
                    kind: PickerSelectionKind::Workspace,
                    pre_parse_check: check_directory(&path),
                    playlist_content: None,
                    guide_content: None,
                }),
            SetupSelectionKind::Playlist => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose playlist")
                .add_filter("Playlist", &["m3u", "m3u8"])
                .pick_file()
                .map(|path| {
                    let pre_parse_check = check_file(&path);
                    let content = if pre_parse_check == PreParseCheck::ReadyToInspect {
                        Some(inspect_playlist_content(&path))
                    } else {
                        None
                    };
                    PickerSelection {
                        kind: PickerSelectionKind::File,
                        pre_parse_check,
                        playlist_content: content,
                        guide_content: None,
                    }
                }),
            SetupSelectionKind::Guide => rfd::FileDialog::new()
                .set_parent(self.window)
                .set_title("Choose guide")
                .add_filter("Guide", &["xml", "xmltv", "gz", "zip"])
                .pick_file()
                .map(|path| {
                    let pre_parse_check = check_file(&path);
                    let content = if pre_parse_check == PreParseCheck::ReadyToInspect {
                        Some(inspect_guide_content(&path))
                    } else {
                        None
                    };
                    PickerSelection {
                        kind: PickerSelectionKind::File,
                        pre_parse_check,
                        playlist_content: None,
                        guide_content: content,
                    }
                }),
        };

        Ok(selection)
    }
}

fn check_directory(path: &Path) -> PreParseCheck {
    match fs::metadata(path) {
        Ok(metadata) if !metadata.is_dir() => {
            PreParseCheck::NeedsAttention(PreParseReason::WrongKind)
        }
        Ok(_) => match fs::read_dir(path) {
            Ok(_) => PreParseCheck::ReadyToInspect,
            Err(error) => PreParseCheck::NeedsAttention(pre_parse_reason(error)),
        },
        Err(error) => PreParseCheck::NeedsAttention(pre_parse_reason(error)),
    }
}

fn check_file(path: &Path) -> PreParseCheck {
    match fs::metadata(path) {
        Ok(metadata) if !metadata.is_file() => {
            PreParseCheck::NeedsAttention(PreParseReason::WrongKind)
        }
        Ok(_) => match fs::File::open(path) {
            Ok(_) => PreParseCheck::ReadyToInspect,
            Err(error) => PreParseCheck::NeedsAttention(pre_parse_reason(error)),
        },
        Err(error) => PreParseCheck::NeedsAttention(pre_parse_reason(error)),
    }
}

const MAX_PLAYLIST_BYTES: u64 = 64 * 1024 * 1024;
const MAX_LOGICAL_LINE_BYTES: usize = 1024 * 1024;

fn inspect_playlist_content(path: &Path) -> PlaylistContentSummary {
    let metadata = match fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(error) => {
            return content_failure(if error.kind() == io::ErrorKind::PermissionDenied {
                PlaylistContentReasonCode::Unreadable
            } else {
                PlaylistContentReasonCode::CheckUnavailable
            })
        }
    };

    if metadata.len() > MAX_PLAYLIST_BYTES {
        return content_failure(PlaylistContentReasonCode::TooLarge);
    }

    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(error) => {
            return content_failure(if error.kind() == io::ErrorKind::PermissionDenied {
                PlaylistContentReasonCode::Unreadable
            } else {
                PlaylistContentReasonCode::CheckUnavailable
            })
        }
    };

    match inspect_playlist_reader(BufReader::new(file)) {
        Ok(entry_count) => PlaylistContentSummary {
            content_status: PlaylistContentStatus::Checked,
            entry_count: Some(entry_count),
            reason_code: None,
        },
        Err(reason_code) => content_failure(reason_code),
    }
}

fn inspect_playlist_reader<R: BufRead>(mut reader: R) -> Result<u64, PlaylistContentReasonCode> {
    let mut line = Vec::new();
    let mut total_bytes = 0_u64;
    let mut first_physical_line = true;
    let mut saw_non_empty_line = false;
    let mut saw_header = false;
    let mut pending_entry = false;
    let mut entry_count = 0_u64;

    loop {
        line.clear();
        let bytes_read = reader
            .read_until(b'\n', &mut line)
            .map_err(content_io_reason)?;
        if bytes_read == 0 {
            break;
        }

        total_bytes = total_bytes.saturating_add(bytes_read as u64);
        if total_bytes > MAX_PLAYLIST_BYTES {
            return Err(PlaylistContentReasonCode::TooLarge);
        }

        let mut logical_length = line.len();
        if line.ends_with(b"\n") {
            logical_length -= 1;
        }
        if logical_length > 0 && line[logical_length - 1] == b'\r' {
            logical_length -= 1;
        }
        if logical_length > MAX_LOGICAL_LINE_BYTES {
            return Err(PlaylistContentReasonCode::TooLarge);
        }

        let mut text =
            std::str::from_utf8(&line).map_err(|_| PlaylistContentReasonCode::InvalidEncoding)?;
        if first_physical_line {
            text = text.strip_prefix('\u{feff}').unwrap_or(text);
            first_physical_line = false;
        }
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        saw_non_empty_line = true;

        if !saw_header {
            if trimmed != "#EXTM3U" {
                return Err(PlaylistContentReasonCode::MissingHeader);
            }
            saw_header = true;
            continue;
        }

        let is_extinf = trimmed
            .as_bytes()
            .get(..8)
            .map_or(false, |prefix| prefix.eq_ignore_ascii_case(b"#EXTINF:"));
        if is_extinf {
            if pending_entry {
                return Err(PlaylistContentReasonCode::IncompleteEntry);
            }
            pending_entry = true;
            continue;
        }

        if trimmed.starts_with('#') {
            continue;
        }

        if !pending_entry {
            return Err(PlaylistContentReasonCode::OrphanStreamLine);
        }

        pending_entry = false;
        entry_count = entry_count.saturating_add(1);
    }

    if !saw_non_empty_line {
        return Err(PlaylistContentReasonCode::EmptyPlaylist);
    }
    if !saw_header {
        return Err(PlaylistContentReasonCode::MissingHeader);
    }
    if pending_entry {
        return Err(PlaylistContentReasonCode::IncompleteEntry);
    }
    if entry_count == 0 {
        return Err(PlaylistContentReasonCode::EmptyPlaylist);
    }

    Ok(entry_count)
}

fn content_io_reason(error: io::Error) -> PlaylistContentReasonCode {
    if error.kind() == io::ErrorKind::PermissionDenied {
        PlaylistContentReasonCode::Unreadable
    } else {
        PlaylistContentReasonCode::CheckUnavailable
    }
}

fn content_failure(reason_code: PlaylistContentReasonCode) -> PlaylistContentSummary {
    PlaylistContentSummary {
        content_status: PlaylistContentStatus::NeedsAttention,
        entry_count: None,
        reason_code: Some(reason_code),
    }
}
const MAX_GUIDE_BYTES: u64 = 64 * 1024 * 1024;
const MAX_GUIDE_COMPRESSED_BYTES: u64 = 64 * 1024 * 1024;
const GUIDE_OUTPUT_LIMIT_ERROR: &str = "guide output exceeds maximum size";

#[derive(Clone, Copy, PartialEq)]
enum GuideContentFormat {
    Plain,
    Gzip,
    Zip,
    Unsupported,
}

fn guide_content_format(path: &Path) -> GuideContentFormat {
    match path.extension().and_then(|extension| extension.to_str()) {
        Some(extension) if extension.eq_ignore_ascii_case("xml") => GuideContentFormat::Plain,
        Some(extension) if extension.eq_ignore_ascii_case("xmltv") => GuideContentFormat::Plain,
        Some(extension) if extension.eq_ignore_ascii_case("gz") => GuideContentFormat::Gzip,
        Some(extension) if extension.eq_ignore_ascii_case("zip") => GuideContentFormat::Zip,
        _ => GuideContentFormat::Unsupported,
    }
}

fn inspect_guide_content(path: &Path) -> GuideContentSummary {
    let format = guide_content_format(path);
    if format == GuideContentFormat::Unsupported {
        return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
    }

    let max_input_bytes = if format == GuideContentFormat::Plain {
        MAX_GUIDE_BYTES
    } else {
        MAX_GUIDE_COMPRESSED_BYTES
    };
    let metadata = match fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(error) => return guide_content_failure(guide_io_reason(&error)),
    };
    if metadata.len() > max_input_bytes {
        return guide_content_failure(GuideContentReasonCode::TooLarge);
    }

    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(error) => return guide_content_failure(guide_io_reason(&error)),
    };

    match format {
        GuideContentFormat::Plain => {
            inspect_guide_reader_summary(BufReader::new(BoundedReader::new(file)))
        }
        GuideContentFormat::Gzip => {
            let decoder = MultiGzDecoder::new(file);
            inspect_guide_reader_summary(BufReader::new(BoundedReader::new(decoder)))
        }
        GuideContentFormat::Zip => inspect_zip_guide(file),
        GuideContentFormat::Unsupported => {
            guide_content_failure(GuideContentReasonCode::UnsupportedFormat)
        }
    }
}

fn inspect_guide_reader_summary<R: BufRead>(reader: R) -> GuideContentSummary {
    match inspect_guide_reader(reader) {
        Ok((channel_count, programme_count)) => GuideContentSummary {
            content_status: GuideContentStatus::Checked,
            channel_count: Some(channel_count),
            programme_count: Some(programme_count),
            reason_code: None,
        },
        Err(reason_code) => guide_content_failure(reason_code),
    }
}

fn inspect_zip_guide(file: fs::File) -> GuideContentSummary {
    let mut archive = match ZipArchive::new(file) {
        Ok(archive) => archive,
        Err(_) => return guide_content_failure(GuideContentReasonCode::UnsupportedFormat),
    };
    if archive.len() == 0 {
        return guide_content_failure(GuideContentReasonCode::EmptyGuide);
    }

    let mut guide_index = None;
    for index in 0..archive.len() {
        let entry = match archive.by_index(index) {
            Ok(entry) => entry,
            Err(_) => return guide_content_failure(GuideContentReasonCode::UnsupportedFormat),
        };
        if entry.is_dir() {
            continue;
        }
        if entry.encrypted() {
            return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
        }
        let extension = Path::new(entry.name())
            .extension()
            .and_then(|extension| extension.to_str());
        if extension.is_some_and(|extension| {
            extension.eq_ignore_ascii_case("gz")
                || extension.eq_ignore_ascii_case("gzip")
                || extension.eq_ignore_ascii_case("zip")
        }) {
            return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
        }
        if !extension.is_some_and(|extension| {
            extension.eq_ignore_ascii_case("xml") || extension.eq_ignore_ascii_case("xmltv")
        }) {
            return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
        }
        if guide_index.replace(index).is_some() {
            return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
        }
        if entry.size() > MAX_GUIDE_BYTES {
            return guide_content_failure(GuideContentReasonCode::TooLarge);
        }
    }

    let Some(guide_index) = guide_index else {
        return guide_content_failure(GuideContentReasonCode::EmptyGuide);
    };
    let entry = match archive.by_index(guide_index) {
        Ok(entry) => entry,
        Err(_) => return guide_content_failure(GuideContentReasonCode::UnsupportedFormat),
    };
    if entry.encrypted() {
        return guide_content_failure(GuideContentReasonCode::UnsupportedFormat);
    }
    inspect_guide_reader_summary(BufReader::new(BoundedReader::new(entry)))
}

fn guide_io_reason(error: &io::Error) -> GuideContentReasonCode {
    if error.kind() == io::ErrorKind::PermissionDenied {
        GuideContentReasonCode::Unreadable
    } else {
        GuideContentReasonCode::CheckUnavailable
    }
}

struct BoundedReader<R> {
    inner: R,
    bytes_read: u64,
}

impl<R: Read> BoundedReader<R> {
    fn new(inner: R) -> Self {
        Self {
            inner,
            bytes_read: 0,
        }
    }
}

impl<R: Read> Read for BoundedReader<R> {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        if buffer.is_empty() {
            return Ok(0);
        }
        if self.bytes_read == MAX_GUIDE_BYTES {
            let mut probe = [0_u8; 1];
            return match self.inner.read(&mut probe) {
                Ok(0) => Ok(0),
                Ok(_) => Err(io::Error::new(
                    io::ErrorKind::Other,
                    GUIDE_OUTPUT_LIMIT_ERROR,
                )),
                Err(error) => Err(error),
            };
        }

        let remaining = MAX_GUIDE_BYTES - self.bytes_read;
        let allowed = usize::try_from(remaining)
            .unwrap_or(usize::MAX)
            .min(buffer.len());
        let bytes_read = self.inner.read(&mut buffer[..allowed])?;
        self.bytes_read = self.bytes_read.saturating_add(bytes_read as u64);
        Ok(bytes_read)
    }
}

fn inspect_guide_reader<R: BufRead>(reader: R) -> Result<(u64, u64), GuideContentReasonCode> {
    let mut reader = Reader::from_reader(reader);
    reader.config_mut().check_end_names = true;
    let mut buffer = Vec::new();
    let mut depth = 0_usize;
    let mut saw_root = false;
    let mut root_closed = false;
    let mut channel_count = 0_u64;
    let mut programme_count = 0_u64;

    loop {
        match reader.read_event_into(&mut buffer) {
            Ok(Event::Start(element)) => {
                if !saw_root {
                    if depth != 0 || element.local_name().as_ref() != "tv" {
                        return Err(GuideContentReasonCode::MissingRoot);
                    }
                    saw_root = true;
                    depth = 1;
                } else if root_closed || depth == 0 {
                    return Err(GuideContentReasonCode::MalformedXml);
                } else {
                    inspect_guide_element(
                        &element,
                        depth,
                        &mut channel_count,
                        &mut programme_count,
                    )?;
                    depth += 1;
                }
            }
            Ok(Event::Empty(element)) => {
                if !saw_root {
                    if element.local_name().as_ref() != "tv" {
                        return Err(GuideContentReasonCode::MissingRoot);
                    }
                    saw_root = true;
                    root_closed = true;
                } else if root_closed || depth == 0 {
                    return Err(GuideContentReasonCode::MalformedXml);
                } else {
                    inspect_guide_element(
                        &element,
                        depth,
                        &mut channel_count,
                        &mut programme_count,
                    )?;
                }
            }
            Ok(Event::End(_)) => {
                if !saw_root || root_closed || depth == 0 {
                    return Err(GuideContentReasonCode::MalformedXml);
                }
                depth -= 1;
                if depth == 0 {
                    root_closed = true;
                }
            }
            Ok(Event::Text(text)) => {
                if depth == 0
                    && text
                        .as_ref()
                        .chars()
                        .any(|character| !character.is_ascii_whitespace())
                {
                    return Err(GuideContentReasonCode::MalformedXml);
                }
            }
            Ok(Event::CData(_)) if depth == 0 => {
                return Err(GuideContentReasonCode::MalformedXml);
            }
            Ok(Event::DocType(_)) | Ok(Event::GeneralRef(_)) => {
                return Err(GuideContentReasonCode::MalformedXml);
            }
            Ok(Event::Eof) => break,
            Ok(_) => {}
            Err(error) => return Err(guide_xml_error(error)),
        }
        buffer.clear();
    }

    if !saw_root {
        return Err(GuideContentReasonCode::MissingRoot);
    }
    if !root_closed || depth != 0 {
        return Err(GuideContentReasonCode::MalformedXml);
    }
    if channel_count == 0 || programme_count == 0 {
        return Err(GuideContentReasonCode::EmptyGuide);
    }

    Ok((channel_count, programme_count))
}

fn inspect_guide_element(
    element: &quick_xml::events::BytesStart<'_>,
    depth: usize,
    channel_count: &mut u64,
    programme_count: &mut u64,
) -> Result<(), GuideContentReasonCode> {
    if depth != 1 {
        return Ok(());
    }

    match element.local_name().as_ref() {
        "channel" => {
            if !guide_has_non_empty_attribute(element, "id")? {
                return Err(GuideContentReasonCode::IncompleteChannel);
            }
            *channel_count = channel_count.saturating_add(1);
        }
        "programme" => {
            if !guide_has_non_empty_attribute(element, "channel")?
                || !guide_has_non_empty_attribute(element, "start")?
                || !guide_has_non_empty_attribute(element, "stop")?
            {
                return Err(GuideContentReasonCode::IncompleteProgramme);
            }
            *programme_count = programme_count.saturating_add(1);
        }
        _ => {}
    }

    Ok(())
}

fn guide_xml_error(error: quick_xml::Error) -> GuideContentReasonCode {
    match error {
        quick_xml::Error::Io(error) if error.to_string() == GUIDE_OUTPUT_LIMIT_ERROR => {
            GuideContentReasonCode::TooLarge
        }
        quick_xml::Error::Io(error)
            if matches!(
                error.kind(),
                io::ErrorKind::InvalidData | io::ErrorKind::UnexpectedEof
            ) =>
        {
            GuideContentReasonCode::MalformedXml
        }
        quick_xml::Error::Io(error) => guide_io_reason(&error),
        quick_xml::Error::Encoding(_) => GuideContentReasonCode::InvalidEncoding,
        _ => GuideContentReasonCode::MalformedXml,
    }
}

fn guide_has_non_empty_attribute(
    element: &quick_xml::events::BytesStart<'_>,
    name: &str,
) -> Result<bool, GuideContentReasonCode> {
    let mut found = false;
    for attribute in element.attributes().with_checks(true) {
        let attribute = attribute.map_err(|_| GuideContentReasonCode::MalformedXml)?;
        if attribute.key.as_ref() == name {
            found = attribute
                .value
                .as_ref()
                .chars()
                .any(|character| !character.is_ascii_whitespace());
        }
    }
    Ok(found)
}

fn guide_content_failure(reason_code: GuideContentReasonCode) -> GuideContentSummary {
    GuideContentSummary {
        content_status: GuideContentStatus::NeedsAttention,
        channel_count: None,
        programme_count: None,
        reason_code: Some(reason_code),
    }
}

fn pre_parse_reason(error: io::Error) -> PreParseReason {
    match error.kind() {
        io::ErrorKind::NotFound => PreParseReason::NotFound,
        io::ErrorKind::PermissionDenied => PreParseReason::NotReadable,
        _ => PreParseReason::CheckUnavailable,
    }
}

fn selected_result(
    kind: SetupSelectionKind,
    pre_parse_check: PreParseCheck,
    playlist_content: Option<PlaylistContentSummary>,
    guide_content: Option<GuideContentSummary>,
) -> SetupSelectionResult {
    let (validation_status, reason_code) = match pre_parse_check {
        PreParseCheck::ReadyToInspect => (ValidationStatus::ReadyToInspect, None),
        PreParseCheck::NeedsAttention(reason) => (
            ValidationStatus::NeedsAttention,
            Some(pre_parse_reason_code(reason)),
        ),
    };

    SetupSelectionResult {
        kind,
        outcome: SetupSelectionOutcome::Selected,
        selection_status: SelectionStatus::Selected,
        validation_status,
        reason_code,
        playlist_content: if kind == SetupSelectionKind::Playlist {
            playlist_content
        } else {
            None
        },
        guide_content: if kind == SetupSelectionKind::Guide {
            guide_content
        } else {
            None
        },
    }
}

fn pre_parse_reason_code(reason: PreParseReason) -> PickerReasonCode {
    match reason {
        PreParseReason::NotFound => PickerReasonCode::NotFound,
        PreParseReason::WrongKind => PickerReasonCode::WrongKind,
        PreParseReason::NotReadable => PickerReasonCode::NotReadable,
        PreParseReason::CheckUnavailable => PickerReasonCode::CheckUnavailable,
    }
}

fn cancelled_result(kind: SetupSelectionKind) -> SetupSelectionResult {
    SetupSelectionResult {
        kind,
        outcome: SetupSelectionOutcome::Cancelled,
        selection_status: SelectionStatus::NotSelected,
        validation_status: ValidationStatus::NotChecked,
        reason_code: None,
        playlist_content: None,
        guide_content: None,
    }
}

fn error_result(
    kind: SetupSelectionKind,
    outcome: SetupSelectionOutcome,
    reason_code: PickerReasonCode,
) -> SetupSelectionResult {
    SetupSelectionResult {
        kind,
        outcome,
        selection_status: SelectionStatus::NotSelected,
        validation_status: ValidationStatus::NotChecked,
        reason_code: Some(reason_code),
        playlist_content: None,
        guide_content: None,
    }
}

fn choose_setup_item_with_adapter(
    kind: SetupSelectionKind,
    adapter: &dyn PickerAdapter,
) -> SetupSelectionResult {
    match adapter.pick(kind) {
        Ok(Some(selection)) if selection.kind.matches(kind) => selected_result(
            kind,
            selection.pre_parse_check,
            selection.playlist_content,
            selection.guide_content,
        ),
        Ok(Some(_)) => error_result(
            kind,
            SetupSelectionOutcome::Rejected,
            PickerReasonCode::WrongKind,
        ),
        Ok(None) => cancelled_result(kind),
        Err(PickerError::Unavailable) => error_result(
            kind,
            SetupSelectionOutcome::Unavailable,
            PickerReasonCode::PickerUnavailable,
        ),
        Err(PickerError::PermissionDenied) => error_result(
            kind,
            SetupSelectionOutcome::Rejected,
            PickerReasonCode::PermissionDenied,
        ),
        Err(PickerError::Unknown) => error_result(
            kind,
            SetupSelectionOutcome::Rejected,
            PickerReasonCode::Unknown,
        ),
    }
}

mod command {
    use super::*;

    #[tauri::command]
    pub async fn choose_setup_item(
        kind: SetupSelectionKind,
        window: Window,
    ) -> SetupSelectionResult {
        choose_setup_item_with_adapter(kind, &NativePicker { window: &window })
    }
}

pub use command::choose_setup_item;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![command::choose_setup_item])
        .run(tauri::generate_context!())
        .expect("error while running ChannelForge");
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FakePicker {
        result: Result<Option<PickerSelection>, PickerError>,
    }

    impl PickerAdapter for FakePicker {
        fn pick(&self, _kind: SetupSelectionKind) -> Result<Option<PickerSelection>, PickerError> {
            self.result
        }
    }

    fn ready_selection(kind: PickerSelectionKind) -> PickerSelection {
        PickerSelection {
            kind,
            pre_parse_check: PreParseCheck::ReadyToInspect,
            playlist_content: None,
            guide_content: None,
        }
    }

    fn scan(content: &str) -> Result<u64, PlaylistContentReasonCode> {
        inspect_playlist_reader(std::io::Cursor::new(content.as_bytes()))
    }

    fn scan_guide(content: &str) -> Result<(u64, u64), GuideContentReasonCode> {
        inspect_guide_reader(std::io::Cursor::new(content.as_bytes()))
    }

    fn guide_test_path(extension: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!(
            "channelforge-guide-{}-{}.{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("system clock should be after epoch")
                .as_nanos(),
            extension
        ))
    }

    fn write_guide_file(extension: &str, bytes: &[u8]) -> std::path::PathBuf {
        let path = guide_test_path(extension);
        fs::write(&path, bytes).expect("guide fixture should be written");
        path
    }

    fn valid_guide_xml() -> &'static [u8] {
        br#"<tv><channel id="channel" /><programme channel="channel" start="start" stop="stop" /></tv>"#
    }

    fn gzip_guide(content: &[u8]) -> Vec<u8> {
        use std::io::Write;

        let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        encoder
            .write_all(content)
            .expect("gzip fixture should be written");
        encoder.finish().expect("gzip fixture should finish")
    }

    fn zip_guide(entries: &[(&str, &[u8])]) -> Vec<u8> {
        use std::io::Write;

        let cursor = std::io::Cursor::new(Vec::new());
        let mut writer = zip::ZipWriter::new(cursor);
        for (name, content) in entries {
            writer
                .start_file(*name, zip::write::SimpleFileOptions::default())
                .expect("zip entry should start");
            writer
                .write_all(content)
                .expect("zip entry should be written");
        }
        writer
            .finish()
            .expect("zip fixture should finish")
            .into_inner()
    }

    #[test]
    fn scans_complete_m3u_entries_without_retaining_content() {
        let entries = scan("#EXTM3U\n#EXTINF:-1,One\nhttps://secret.example/one\n#EXTINF:-1,Two\nhttps://secret.example/two\n")
            .expect("valid playlist should scan");

        assert_eq!(entries, 2);
    }

    #[test]
    fn accepts_bom_comments_and_blank_lines() {
        let entries = scan("\u{feff}#EXTM3U\n\n#EXT-X-VERSION:3\n#EXTINF:-1,One\nopaque-stream\n")
            .expect("valid playlist should scan");

        assert_eq!(entries, 1);
    }

    #[test]
    fn maps_structural_failures_to_safe_reasons() {
        let cases = [
            ("", PlaylistContentReasonCode::EmptyPlaylist),
            (
                "#EXTINF:-1,One\nopaque-stream\n",
                PlaylistContentReasonCode::MissingHeader,
            ),
            (
                "#EXTM3U\n#EXTINF:-1,One\n",
                PlaylistContentReasonCode::IncompleteEntry,
            ),
            (
                "#EXTM3U\nopaque-stream\n",
                PlaylistContentReasonCode::OrphanStreamLine,
            ),
            (
                "#EXTM3U\n#EXTINF:-1,One\n#EXTINF:-1,Two\nopaque-stream\n",
                PlaylistContentReasonCode::IncompleteEntry,
            ),
        ];

        for (content, reason_code) in cases {
            assert_eq!(scan(content), Err(reason_code));
        }
    }

    #[test]
    fn scans_direct_xmltv_channels_and_programmes_without_retaining_content() {
        let counts = scan_guide(
            "\u{feff}<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
             <tv generator-info-name=\"hidden-generator\">\n\
               <!-- hidden comment -->\n\
               <channel id=\"hidden-channel\"><display-name>Hidden Channel</display-name><icon src=\"https://example.invalid/hidden.png\" /></channel>\n\
               <metadata><channel id=\"nested-channel\" /></metadata>\n\
               <programme channel=\"hidden-channel\" start=\"hidden-start\" stop=\"hidden-stop\"><title>Hidden Programme</title><desc>Hidden description</desc></programme>\n\
               <programme channel=\"hidden-channel\" start=\"another-start\" stop=\"another-stop\" />\n\
             </tv>",
        )
        .expect("valid XMLTV should scan");

        assert_eq!(counts, (1, 2));
    }

    #[test]
    fn maps_xmltv_structural_failures_to_safe_reasons() {
        let cases = [
            ("<guide />", GuideContentReasonCode::MissingRoot),
            ("<tv />", GuideContentReasonCode::EmptyGuide),
            (
                "<tv><channel /></tv>",
                GuideContentReasonCode::IncompleteChannel,
            ),
            (
                "<tv><channel id=\"channel\" /><programme start=\"start\" stop=\"stop\" /></tv>",
                GuideContentReasonCode::IncompleteProgramme,
            ),
            (
                "<tv><channel id=\"channel\"><display-name>Channel</display-name></tv>",
                GuideContentReasonCode::MalformedXml,
            ),
            (
                "<!DOCTYPE tv SYSTEM \"https://example.invalid/guide.dtd\"><tv />",
                GuideContentReasonCode::MalformedXml,
            ),
        ];

        for (content, reason_code) in cases {
            assert_eq!(scan_guide(content), Err(reason_code));
        }
    }

    #[test]
    fn scans_gzip_and_single_guide_zip_payloads() {
        let gzip_path = write_guide_file("gz", &gzip_guide(valid_guide_xml()));
        let gzip_summary = inspect_guide_content(&gzip_path);
        assert_eq!(gzip_summary.content_status, GuideContentStatus::Checked);
        assert_eq!(gzip_summary.channel_count, Some(1));
        assert_eq!(gzip_summary.programme_count, Some(1));
        fs::remove_file(&gzip_path).expect("gzip fixture should be removed");

        let zip_path = write_guide_file("zip", &zip_guide(&[("guide.xml", valid_guide_xml())]));
        let zip_summary = inspect_guide_content(&zip_path);
        assert_eq!(zip_summary.content_status, GuideContentStatus::Checked);
        assert_eq!(zip_summary.channel_count, Some(1));
        assert_eq!(zip_summary.programme_count, Some(1));
        fs::remove_file(&zip_path).expect("zip fixture should be removed");
    }

    #[test]
    fn rejects_invalid_encoding_and_unsafe_compressed_guides() {
        let invalid_path = write_guide_file("xml", b"<tv>\xff</tv>");
        let invalid = inspect_guide_content(&invalid_path);
        assert_eq!(
            invalid.reason_code,
            Some(GuideContentReasonCode::InvalidEncoding)
        );
        fs::remove_file(&invalid_path).expect("invalid fixture should be removed");

        let malformed_gzip_path = write_guide_file("gz", b"not-gzip");
        let malformed_gzip = inspect_guide_content(&malformed_gzip_path);
        assert_eq!(
            malformed_gzip.reason_code,
            Some(GuideContentReasonCode::MalformedXml)
        );
        fs::remove_file(&malformed_gzip_path).expect("malformed gzip fixture should be removed");

        let empty_zip_path = write_guide_file("zip", &zip_guide(&[]));
        let empty_zip = inspect_guide_content(&empty_zip_path);
        assert_eq!(
            empty_zip.reason_code,
            Some(GuideContentReasonCode::EmptyGuide)
        );
        fs::remove_file(&empty_zip_path).expect("empty zip fixture should be removed");

        let multi_guide_path = write_guide_file(
            "zip",
            &zip_guide(&[
                ("first.xml", valid_guide_xml()),
                ("second.xmltv", valid_guide_xml()),
            ]),
        );
        let multi_guide = inspect_guide_content(&multi_guide_path);
        assert_eq!(
            multi_guide.reason_code,
            Some(GuideContentReasonCode::UnsupportedFormat)
        );
        fs::remove_file(&multi_guide_path).expect("multi-guide fixture should be removed");

        let nested_path = write_guide_file("zip", &zip_guide(&[("guide.xml.gz", b"nested")]));
        let nested = inspect_guide_content(&nested_path);
        assert_eq!(
            nested.reason_code,
            Some(GuideContentReasonCode::UnsupportedFormat)
        );
        fs::remove_file(&nested_path).expect("nested fixture should be removed");

        let ambiguous_path = write_guide_file(
            "zip",
            &zip_guide(&[
                ("guide.xml", valid_guide_xml()),
                ("README.txt", b"ambiguous"),
            ]),
        );
        let ambiguous = inspect_guide_content(&ambiguous_path);
        assert_eq!(
            ambiguous.reason_code,
            Some(GuideContentReasonCode::UnsupportedFormat)
        );
        fs::remove_file(&ambiguous_path).expect("ambiguous fixture should be removed");

        let oversized_path = guide_test_path("gz");
        let oversized_file = fs::File::create(&oversized_path).expect("fixture should be created");
        oversized_file
            .set_len(MAX_GUIDE_COMPRESSED_BYTES + 1)
            .expect("fixture should be oversized");
        let oversized = inspect_guide_content(&oversized_path);
        assert_eq!(
            oversized.reason_code,
            Some(GuideContentReasonCode::TooLarge)
        );
        fs::remove_file(&oversized_path).expect("oversized fixture should be removed");

        let mut oversized_xml = valid_guide_xml().to_vec();
        oversized_xml.resize(MAX_GUIDE_BYTES as usize + 1, b' ');
        let oversized_output_path = write_guide_file("gz", &gzip_guide(&oversized_xml));
        let oversized_output = inspect_guide_content(&oversized_output_path);
        assert_eq!(
            oversized_output.reason_code,
            Some(GuideContentReasonCode::TooLarge)
        );
        fs::remove_file(&oversized_output_path)
            .expect("oversized output fixture should be removed");
    }

    #[test]
    fn bounded_reader_rejects_output_beyond_final_guide_limit() {
        let mut reader = BoundedReader::new(std::io::repeat(0));
        let mut chunk = vec![0_u8; 1024 * 1024];
        let error = loop {
            match reader.read(&mut chunk) {
                Ok(_) => {}
                Err(error) => break error,
            }
        };

        assert_eq!(error.kind(), io::ErrorKind::Other);
        assert_eq!(error.to_string(), GUIDE_OUTPUT_LIMIT_ERROR);
    }

    #[test]
    fn serializes_guide_summary_without_native_or_raw_values() {
        let summary = GuideContentSummary {
            content_status: GuideContentStatus::Checked,
            channel_count: Some(2),
            programme_count: Some(4),
            reason_code: None,
        };
        let serialized = serde_json::to_value(summary).expect("summary should serialize");
        let serialized_text = serialized.to_string();

        assert_eq!(serialized["contentStatus"], "checked");
        assert_eq!(serialized["channelCount"], 2);
        assert_eq!(serialized["programmeCount"], 4);
        assert!(serialized["reasonCode"].is_null());
        for forbidden in [
            "hidden-channel",
            "Hidden Programme",
            "https://example.invalid",
            "path",
            "filename",
            "url",
            "credentials",
            "token",
        ] {
            assert!(!serialized_text.contains(forbidden));
        }
    }

    #[test]
    fn rejects_invalid_encoding_and_oversized_lines() {
        let invalid = inspect_playlist_reader(std::io::Cursor::new(vec![
            b'#', b'E', b'X', b'T', b'M', b'3', b'U', b'\n', 0xff,
        ]));
        assert_eq!(invalid, Err(PlaylistContentReasonCode::InvalidEncoding));

        let mut oversized = String::from("#EXTM3U\n#EXTINF:-1,One\n");
        oversized.push_str(&"x".repeat(MAX_LOGICAL_LINE_BYTES + 1));
        oversized.push('\n');
        assert_eq!(scan(&oversized), Err(PlaylistContentReasonCode::TooLarge));
    }

    #[test]
    fn serializes_content_summary_without_native_or_raw_values() {
        let summary = PlaylistContentSummary {
            content_status: PlaylistContentStatus::Checked,
            entry_count: Some(2),
            reason_code: None,
        };
        let serialized = serde_json::to_value(summary).expect("summary should serialize");

        assert_eq!(serialized["contentStatus"], "checked");
        assert_eq!(serialized["entryCount"], 2);
        assert!(serialized.get("path").is_none());
        assert!(serialized.get("filename").is_none());
        assert!(serialized.get("url").is_none());
        assert!(serialized.get("contents").is_none());
    }
    #[test]
    fn accepts_workspace_playlist_and_guide_without_returning_native_values() {
        let cases = [
            (
                SetupSelectionKind::Workspace,
                ready_selection(PickerSelectionKind::Workspace),
            ),
            (
                SetupSelectionKind::Playlist,
                ready_selection(PickerSelectionKind::File),
            ),
            (
                SetupSelectionKind::Guide,
                ready_selection(PickerSelectionKind::File),
            ),
        ];

        for (kind, selection) in cases {
            let result = choose_setup_item_with_adapter(
                kind,
                &FakePicker {
                    result: Ok(Some(selection)),
                },
            );

            assert_eq!(
                result,
                selected_result(kind, PreParseCheck::ReadyToInspect, None, None)
            );
            assert!(!format!("{result:?}").contains("path"));
            assert!(!format!("{result:?}").contains("filename"));
        }
    }

    #[test]
    fn maps_pre_parse_failures_to_attention_without_exposing_native_values() {
        let cases = [
            (PreParseReason::NotFound, PickerReasonCode::NotFound),
            (PreParseReason::WrongKind, PickerReasonCode::WrongKind),
            (PreParseReason::NotReadable, PickerReasonCode::NotReadable),
            (
                PreParseReason::CheckUnavailable,
                PickerReasonCode::CheckUnavailable,
            ),
        ];

        for (reason, reason_code) in cases {
            let result = choose_setup_item_with_adapter(
                SetupSelectionKind::Playlist,
                &FakePicker {
                    result: Ok(Some(PickerSelection {
                        kind: PickerSelectionKind::File,
                        pre_parse_check: PreParseCheck::NeedsAttention(reason),
                        playlist_content: None,
                        guide_content: None,
                    })),
                },
            );

            assert_eq!(result.outcome, SetupSelectionOutcome::Selected);
            assert_eq!(result.selection_status, SelectionStatus::Selected);
            assert_eq!(result.validation_status, ValidationStatus::NeedsAttention);
            assert_eq!(result.reason_code, Some(reason_code));
            assert!(!format!("{result:?}").contains("path"));
        }
    }

    #[test]
    fn serializes_only_safe_selection_fields() {
        let serialized = serde_json::to_value(selected_result(
            SetupSelectionKind::Playlist,
            PreParseCheck::ReadyToInspect,
            Some(PlaylistContentSummary {
                content_status: PlaylistContentStatus::Checked,
                entry_count: Some(2),
                reason_code: None,
            }),
            None,
        ))
        .expect("selection result should serialize");

        assert_eq!(serialized["kind"], "playlist");
        assert_eq!(serialized["outcome"], "selected");
        assert_eq!(serialized["selectionStatus"], "selected");
        assert_eq!(serialized["validationStatus"], "ready-to-inspect");
        assert!(serialized["reasonCode"].is_null());
        assert!(serialized["playlistContent"]["reasonCode"].is_null());
        assert_eq!(serialized["playlistContent"]["contentStatus"], "checked");
        assert_eq!(serialized["playlistContent"]["entryCount"], 2);
        assert!(serialized.get("path").is_none());
        assert!(serialized.get("filename").is_none());
        assert!(serialized.get("contents").is_none());
        assert!(serialized.get("url").is_none());
        assert!(serialized.get("token").is_none());
    }

    #[test]
    fn serializes_guide_content_only_as_safe_aggregate_fields() {
        let serialized = serde_json::to_value(selected_result(
            SetupSelectionKind::Guide,
            PreParseCheck::ReadyToInspect,
            None,
            Some(GuideContentSummary {
                content_status: GuideContentStatus::Checked,
                channel_count: Some(2),
                programme_count: Some(4),
                reason_code: None,
            }),
        ))
        .expect("selection result should serialize");
        let serialized_text = serialized.to_string();

        assert_eq!(serialized["kind"], "guide");
        assert_eq!(serialized["guideContent"]["contentStatus"], "checked");
        assert_eq!(serialized["guideContent"]["channelCount"], 2);
        assert_eq!(serialized["guideContent"]["programmeCount"], 4);
        assert!(serialized.get("playlistContent").is_none());
        for forbidden in [
            "path",
            "filename",
            "url",
            "title",
            "channel-id",
            "credentials",
            "token",
        ] {
            assert!(!serialized_text.contains(forbidden));
        }
    }

    #[test]
    fn cancellation_keeps_selection_unselected_and_unchecked() {
        let result = choose_setup_item_with_adapter(
            SetupSelectionKind::Workspace,
            &FakePicker { result: Ok(None) },
        );

        assert_eq!(result, cancelled_result(SetupSelectionKind::Workspace));
    }

    #[test]
    fn rejects_wrong_picker_kind_without_exposing_the_native_selection() {
        let result = choose_setup_item_with_adapter(
            SetupSelectionKind::Workspace,
            &FakePicker {
                result: Ok(Some(ready_selection(PickerSelectionKind::File))),
            },
        );

        assert_eq!(
            result,
            error_result(
                SetupSelectionKind::Workspace,
                SetupSelectionOutcome::Rejected,
                PickerReasonCode::WrongKind,
            )
        );
        assert!(!format!("{result:?}").contains("path"));
    }

    #[test]
    fn maps_picker_errors_to_safe_codes() {
        let cases = [
            (
                PickerError::Unavailable,
                SetupSelectionOutcome::Unavailable,
                PickerReasonCode::PickerUnavailable,
            ),
            (
                PickerError::PermissionDenied,
                SetupSelectionOutcome::Rejected,
                PickerReasonCode::PermissionDenied,
            ),
            (
                PickerError::Unknown,
                SetupSelectionOutcome::Rejected,
                PickerReasonCode::Unknown,
            ),
        ];

        for (error, outcome, reason_code) in cases {
            let result = choose_setup_item_with_adapter(
                SetupSelectionKind::Guide,
                &FakePicker { result: Err(error) },
            );

            assert_eq!(
                result,
                error_result(SetupSelectionKind::Guide, outcome, reason_code)
            );
        }
    }
}
