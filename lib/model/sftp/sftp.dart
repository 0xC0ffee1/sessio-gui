import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sessio_ui/model/sftp/browser.dart';
import 'package:sessio_ui/src/generated/client_ipc.pbgrpc.dart';

class SftpBrowser extends FileBrowser {
  List<String> _currentPath = [];
  List<FileMeta> _currentFiles = [];
  bool _isLoadingFiles = false;

  TransferData? _currentTransfer;

  final ClientIPCClient _client;
  final String _sessionId;

  SftpBrowser(this._client, this._sessionId);

  // File operations
  @override
  Stream<TransferStatus> addFile(String localPath, String fileName) {
    final remotePath =
        _currentPath.isEmpty ? fileName : "${_currentPath.join('/')}/$fileName";
    final responseStream = _client.fileUpload(FileTransferRequest(
        sessionId: _sessionId, localPath: localPath, remotePath: remotePath));

    return _createTransferStream(responseStream);
  }

  @override
  Stream<TransferStatus> copyFile(String fileName, String dest) {
    final remotePath =
        _currentPath.isEmpty ? fileName : "${_currentPath.join('/')}/$fileName";

    print(remotePath);

    final responseStream = _client.fileDownload(FileTransferRequest(
      sessionId: _sessionId,
      localPath: dest,
      remotePath: remotePath,
    ));

    return _createTransferStream(responseStream);
  }

  Stream<TransferStatus> _createTransferStream(
      Stream<FileTransferStatus> responseStream) {
    final StreamController<TransferStatus> controller =
        StreamController<TransferStatus>.broadcast();

    responseStream.listen((response) {
      switch (response.whichTyp()) {
        case FileTransferStatus_Typ.progress:
          controller.add(
              TransferStatus.progress(bytesRead: response.progress.bytesRead));
          break;
        case FileTransferStatus_Typ.completed:
          controller.add(TransferStatus.completed());
          break;
        case FileTransferStatus_Typ.notSet:
          break;
      }
    }, onDone: () {
      controller.close();
    }, onError: (error) {
      controller.addError(error);
      controller.close();
    });

    return controller.stream;
  }

  // Navigation methods
  @override
  List<String> get currentPath => _currentPath;

  @override
  Future<List<FileMeta>> refreshFileList() async {
    _isLoadingFiles = true;
    notifyListeners();

    FileList remoteList = await _client.listDirectory(
        Path(sessionId: _sessionId, path: _currentPath.join("/")));

    _currentFiles = remoteList.files.map((file) {
      return FileMeta(
        filename: file.fileName,
        path: file.filePath,
        byteSize: file.fileSize.toInt(),
        isDir: file.isDir,
      );
    }).toList();

    _isLoadingFiles = false;
    notifyListeners();
    return _currentFiles;
  }

  @override
  bool get isLoading => _isLoadingFiles;

  @override
  Future<void> navigateToDirectory(String directory) async {
    _currentPath.add(directory);
    await refreshFileList();
  }

  @override
  Future<void> navigateUp() async {
    if (_currentPath.isNotEmpty) {
      _currentPath.removeLast();
    }
    await refreshFileList();
  }

  @override
  Future<void> setCurrentPath(List<String> path) async {
    _currentPath = path;
    await refreshFileList();
  }

  @override
  List<FileMeta> get currentFiles => _currentFiles;

  // Transfer-related methods
  @override
  TransferData? getCurrentTransfer() => _currentTransfer;

  @override
  void setCurrentTransferData(TransferData data) {
    _currentTransfer = data;
    notifyListeners();
  }

  @override
  void setTransferCancelled() {
    _currentTransfer = null;
    notifyListeners();
  }

  // Bulk selection management
  final List<FileMeta> _selectedFiles = [];

  @override
  List<FileMeta> get selectedFiles => List.unmodifiable(_selectedFiles);

  @override
  void toggleFileSelection(FileMeta file) {
    if (_selectedFiles.contains(file)) {
      _selectedFiles.remove(file);
    } else {
      _selectedFiles.add(file);
    }
    notifyListeners();
  }

  @override
  void clearSelection() {
    _selectedFiles.clear();
    notifyListeners();
  }

  @override
  void selectAllFiles() {
    _selectedFiles.clear();
    _selectedFiles.addAll(_currentFiles);
    notifyListeners();
  }

  @override
  void deselectAllFiles() {
    _selectedFiles.clear();
    notifyListeners();
  }

  @override
  bool isFileSelected(FileMeta file) => _selectedFiles.contains(file);

  // Bulk operations
  @override
  Future<void> deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    final data = _selectedFiles
        .map((file) => FileDelData(path: file.path, isDir: file.isDir))
        .toList();
    final request = FileDeleteRequest(sessionId: _sessionId, data: data);

    await _client.fileDelete(request);
    clearSelection();
    await refreshFileList();
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    final request = FileRenameRequest(
      sessionId: _sessionId,
      oldPath: oldPath,
      newPath: newPath,
    );
    await _client.fileRename(request);
    await refreshFileList();
  }
}
