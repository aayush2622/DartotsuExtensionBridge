/// Everything a download needs below the queue: streaming file and HLS
/// fetchers, manga page and novel image fetchers, comic and book archives, the
/// on-disk layout and a speed pacer. Uses the host's network through
/// `BridgeNetwork.downloadClient`; the HLS to mp4 step runs on `FfmpegAddon`.
library;

export './Downloads/Archives.dart';
export './Downloads/BookText.dart';
export './Downloads/ChapterDownload.dart';
export './Downloads/DashDownload.dart';
export './Downloads/DownloadCancel.dart';
export './Downloads/DownloadPaths.dart';
export './Downloads/FileFetcher.dart';
export './Downloads/HlsDownload.dart';
export './Downloads/HttpStream.dart';
export './Downloads/Throttle.dart';
