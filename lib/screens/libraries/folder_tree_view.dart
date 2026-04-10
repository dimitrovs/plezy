import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../../models/plex_metadata.dart';
import '../../providers/download_provider.dart';
import '../../services/play_queue_launcher.dart';
import '../../utils/app_logger.dart';
import '../../utils/media_navigation_helper.dart';
import '../../utils/provider_extensions.dart';
import '../../utils/snackbar_helper.dart';
import '../../i18n/strings.g.dart';
import '../music/music_player_screen.dart';
import 'folder_tree_item.dart';
import 'state_messages.dart';

/// Expandable tree view for browsing library folders
/// Shows a hierarchical file/folder structure
class FolderTreeView extends StatefulWidget {
  final String libraryKey;
  final String? serverId; // Server this library belongs to
  final bool isMusicLibrary;
  final void Function(String)? onRefresh;
  final FocusNode? firstItemFocusNode;
  final VoidCallback? onNavigateUp;

  const FolderTreeView({
    super.key,
    required this.libraryKey,
    this.serverId,
    this.isMusicLibrary = false,
    this.onRefresh,
    this.firstItemFocusNode,
    this.onNavigateUp,
  });

  @override
  State<FolderTreeView> createState() => _FolderTreeViewState();
}

class _FolderTreeViewState extends State<FolderTreeView> {
  List<PlexMetadata> _rootFolders = [];
  final Map<String, List<PlexMetadata>> _childrenCache = {};
  final Set<String> _expandedFolders = {};
  final Set<String> _loadingFolders = {};
  bool _isLoadingRoot = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRootFolders();
  }

  Future<void> _loadRootFolders() async {
    setState(() {
      _isLoadingRoot = true;
      _errorMessage = null;
    });

    try {
      final client = context.getClientForServer(widget.serverId!);

      final folders = await client.getLibraryFolders(widget.libraryKey);

      if (!mounted) return;

      final taggedFolders = folders
          .map(
            (folder) => folder.copyWith(
              serverId: widget.serverId!,
              serverName: null, // server name not required for folders listing
            ),
          )
          .toList();

      setState(() {
        _rootFolders = taggedFolders;
        _isLoadingRoot = false;
      });

      appLogger.d('Loaded ${folders.length} root folders');
    } catch (e) {
      if (!mounted) return;

      appLogger.e('Failed to load root folders', error: e);
      setState(() {
        _errorMessage = t.errors.failedToLoad(context: t.libraries.folders, error: e.toString());
        _isLoadingRoot = false;
      });
    }
  }

  Future<void> _loadFolderChildren(PlexMetadata folder) async {
    // Already loading this folder
    if (_loadingFolders.contains(folder.key!)) return;

    // Already loaded and cached
    if (_childrenCache.containsKey(folder.key!)) {
      setState(() {
        _expandedFolders.add(folder.key!);
      });
      return;
    }

    setState(() {
      _loadingFolders.add(folder.key!);
    });

    try {
      final client = context.getClientForServer(widget.serverId!);

      // Items are automatically tagged with server info by PlexClient
      final children = await client.getFolderChildren(folder.key!);

      if (!mounted) return;

      setState(() {
        _childrenCache[folder.key!] = children;
        _expandedFolders.add(folder.key!);
        _loadingFolders.remove(folder.key!);
      });

      appLogger.d('Loaded ${children.length} children for folder: ${folder.title}');
    } catch (e) {
      if (!mounted) return;

      appLogger.e('Failed to load folder children', error: e);
      setState(() {
        _loadingFolders.remove(folder.key!);
      });

      if (mounted) {
        showErrorSnackBar(context, t.errors.failedToLoad(context: t.libraries.folders, error: e.toString()));
      }
    }
  }

  void _toggleFolder(PlexMetadata folder) {
    if (_expandedFolders.contains(folder.key!)) {
      setState(() {
        _expandedFolders.remove(folder.key!);
      });
    } else {
      _loadFolderChildren(folder);
    }
  }

  Future<void> _handleItemTap(PlexMetadata item) async {
    if (widget.isMusicLibrary && item.mediaType == PlexMediaType.track) {
      // For music tracks in folder view, build a playlist from sibling tracks
      final parentKey = _findParentKey(item);
      final siblings = parentKey != null ? _childrenCache[parentKey] : _rootFolders;
      final tracks = (siblings ?? []).where((s) => !_isFolder(s)).toList();
      final index = tracks.indexWhere((t) => t.key == item.key);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MusicPlayerScreen(
            track: item,
            playlist: tracks,
            initialIndex: index >= 0 ? index : 0,
          ),
        ),
      );
      return;
    }
    await navigateToMediaItem(context, item, onRefresh: widget.onRefresh);
  }

  /// Find the parent folder key for a given item by searching the children cache
  String? _findParentKey(PlexMetadata item) {
    for (final entry in _childrenCache.entries) {
      if (entry.value.any((child) => child.key == item.key)) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> _handleFolderPlay(PlexMetadata folder) async {
    if (widget.isMusicLibrary) {
      await _playMusicFolder(folder, shuffle: false);
      return;
    }
    final client = context.getClientForServer(widget.serverId!);
    final launcher = PlayQueueLauncher(context: context, client: client, serverId: widget.serverId);
    await launcher.launchFromFolder(folderKey: folder.key!, shuffle: false);
  }

  Future<void> _handleFolderShuffle(PlexMetadata folder) async {
    if (widget.isMusicLibrary) {
      await _playMusicFolder(folder, shuffle: true);
      return;
    }
    final client = context.getClientForServer(widget.serverId!);
    final launcher = PlayQueueLauncher(context: context, client: client, serverId: widget.serverId);
    await launcher.launchFromFolder(folderKey: folder.key!, shuffle: true);
  }

  /// Play all tracks in a music folder using MusicPlayerScreen
  Future<void> _playMusicFolder(PlexMetadata folder, {required bool shuffle}) async {
    try {
      // Load children if not cached
      List<PlexMetadata> children;
      if (_childrenCache.containsKey(folder.key!)) {
        children = _childrenCache[folder.key!]!;
      } else {
        final client = context.getClientForServer(widget.serverId!);
        children = await client.getFolderChildren(folder.key!);
        if (!mounted) return;
        _childrenCache[folder.key!] = children;
      }

      // Collect all tracks (non-folder items)
      final tracks = children.where((item) => !_isFolder(item)).toList();
      if (tracks.isEmpty) {
        if (mounted) showErrorSnackBar(context, t.music.noTracks);
        return;
      }

      if (shuffle) tracks.shuffle();

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MusicPlayerScreen(
            track: tracks.first,
            playlist: tracks,
            initialIndex: 0,
          ),
        ),
      );
    } catch (e) {
      appLogger.e('Failed to play music folder', error: e);
      if (mounted) {
        showErrorSnackBar(context, e.toString());
      }
    }
  }

  Future<void> _handleDownloadTrack(PlexMetadata track) async {
    if (!widget.isMusicLibrary) return;
    final client = context.getClientForServer(widget.serverId!);
    final downloadProvider = context.read<DownloadProvider>();
    try {
      await downloadProvider.queueDownload(
        track.copyWith(serverId: widget.serverId),
        client,
      );
      if (mounted) {
        showSuccessSnackBar(context, t.downloads.downloadQueued);
      }
    } catch (e) {
      appLogger.e('Failed to queue track download', error: e);
      if (mounted) showErrorSnackBar(context, e.toString());
    }
  }

  Future<void> _handleDownloadFolder(PlexMetadata folder) async {
    if (!widget.isMusicLibrary) return;
    try {
      final client = context.getClientForServer(widget.serverId!);

      // Load children if not cached
      List<PlexMetadata> children;
      if (_childrenCache.containsKey(folder.key!)) {
        children = _childrenCache[folder.key!]!;
      } else {
        children = await client.getFolderChildren(folder.key!);
        if (!mounted) return;
        _childrenCache[folder.key!] = children;
      }

      final tracks = children.where((item) => !_isFolder(item)).toList();
      if (tracks.isEmpty) {
        if (mounted) showErrorSnackBar(context, t.music.noTracks);
        return;
      }

      final downloadProvider = context.read<DownloadProvider>();
      int queued = 0;
      for (final track in tracks) {
        try {
          await downloadProvider.queueDownload(
            track.copyWith(serverId: widget.serverId),
            client,
          );
          queued++;
        } catch (e) {
          appLogger.e('Failed to queue track download', error: e);
        }
      }
      if (mounted && queued > 0) {
        showSuccessSnackBar(context, t.downloads.tracksQueued(count: queued));
      }
    } catch (e) {
      appLogger.e('Failed to download folder', error: e);
      if (mounted) showErrorSnackBar(context, e.toString());
    }
  }

  bool _isFolder(PlexMetadata item) {
    // Folders typically don't have a specific type or might have special indicators
    // Check for common folder indicators
    return item.key?.contains('/folder') == true || item.type == null || item.type!.isEmpty || item.mediaType == PlexMediaType.unknown;
  }

  List<Widget> _buildTreeItems(List<PlexMetadata> items, int depth, [String parentPath = '']) {
    final List<Widget> widgets = [];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final isFolder = _isFolder(item);
      final isExpanded = _expandedFolders.contains(item.key);
      final isLoading = _loadingFolders.contains(item.key);

      // Create a unique key path that includes parent hierarchy and index
      final itemPath = parentPath.isEmpty ? '$i' : '$parentPath-$i';

      // First root item gets the external focus node and navigate-up callback
      final isFirstRootItem = depth == 0 && i == 0;

      // Add the item itself
      widgets.add(
        FolderTreeItem(
          key: ValueKey(itemPath),
          item: item,
          depth: depth,
          isFolder: isFolder,
          isMusicLibrary: widget.isMusicLibrary,
          isExpanded: isExpanded,
          isLoading: isLoading,
          onExpand: isFolder ? () => _toggleFolder(item) : null,
          onTap: !isFolder ? () => _handleItemTap(item) : null,
          onPlayAll: isFolder ? () => _handleFolderPlay(item) : null,
          onShuffle: isFolder ? () => _handleFolderShuffle(item) : null,
          onDownload: widget.isMusicLibrary
              ? (isFolder ? () => _handleDownloadFolder(item) : () => _handleDownloadTrack(item))
              : null,
          focusNode: isFirstRootItem ? widget.firstItemFocusNode : null,
          onNavigateUp: isFirstRootItem ? widget.onNavigateUp : null,
        ),
      );

      // Add children if folder is expanded
      if (isFolder && isExpanded && _childrenCache.containsKey(item.key)) {
        final children = _childrenCache[item.key]!;
        widgets.addAll(_buildTreeItems(children, depth + 1, itemPath));
      }
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRoot) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return ErrorStateWidget(
        message: _errorMessage!,
        icon: Symbols.error_outline_rounded,
        onRetry: _loadRootFolders,
        retryLabel: t.common.retry,
      );
    }

    if (_rootFolders.isEmpty) {
      return EmptyStateWidget(message: t.libraries.noFoldersFound, icon: Symbols.folder_open_rounded);
    }

    return RefreshIndicator(
      onRefresh: _loadRootFolders,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: _buildTreeItems(_rootFolders, 0),
      ),
    );
  }
}
