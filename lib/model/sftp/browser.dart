import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sessio_ui/src/generated/client_ipc.pbgrpc.dart';

abstract class FileBrowser with ChangeNotifier {
  List<String> get currentPath;
  List<FileMeta> get currentFiles;
  bool get isLoading;

  // Navigation methods
  Future<void> navigateToDirectory(String directory);
  Future<void> navigateUp();
  Future<void> setCurrentPath(List<String> path);
  Future<List<FileMeta>> refreshFileList();

  // File operations
  Stream<TransferStatus> addFile(String localPath, String fileName);
  Stream<TransferStatus> copyFile(String filePath, String dest);

  // Transfer-related methods
  void setCurrentTransferData(TransferData data);
  TransferData? getCurrentTransfer();
  void setTransferCancelled();

  // Bulk selection methods
  List<FileMeta> get selectedFiles;
  void toggleFileSelection(FileMeta file);
  void clearSelection();
  void selectAllFiles();
  void deselectAllFiles();
  bool isFileSelected(FileMeta file);

  // Bulk operations
  Future<void> deleteSelectedFiles();
  Future<void> renameFile(String oldPath, String newPath);
}

enum TransferStatusType {
  progress,
  completed,
}

class TransferData {
  final int fileSize;
  final Stream<TransferStatus> transferStream;

  const TransferData({required this.fileSize, required this.transferStream});
}

class TransferStatus {
  final TransferStatusType type;
  final int bytesRead;

  const TransferStatus.progress({required this.bytesRead})
      : type = TransferStatusType.progress;
  const TransferStatus.completed()
      : bytesRead = 0,
        type = TransferStatusType.completed;

  int getBytesRead() => bytesRead;
}

class FileMeta {
  final String filename;
  final String path;
  final int byteSize;
  final bool isDir;

  FileMeta({
    required this.filename,
    required this.path,
    required this.byteSize,
    required this.isDir,
  });

  String getFilename() => filename;
  String getPath() => path;
  int getByteSize() => byteSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileMeta &&
          runtimeType == other.runtimeType &&
          filename == other.filename &&
          path == other.path &&
          byteSize == other.byteSize &&
          isDir == other.isDir;

  @override
  int get hashCode =>
      filename.hashCode ^ path.hashCode ^ byteSize.hashCode ^ isDir.hashCode;

  @override
  String toString() {
    return 'FileMeta{filename: $filename, path: $path, byteSize: $byteSize, dir: $isDir}';
  }
}

abstract class LocalFile {
  FileMeta getMeta();
  Future<File> getFileHandle();
}
