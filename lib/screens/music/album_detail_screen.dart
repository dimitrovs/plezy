import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../models/plex_metadata.dart';
import '../../models/download_models.dart';
import '../../providers/download_provider.dart';
import '../../services/plex_client.dart';
import '../../utils/app_logger.dart';
import '../../utils/formatters.dart';
import '../../utils/provider_extensions.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/plex_optimized_image.dart';
import '../../i18n/strings.g.dart';
import 'music_player_screen.dart';

/// Screen showing an album's tracks with download support.
class AlbumDetailScreen extends StatefulWidget {
  final PlexMetadata metadata;
  final bool isOffline;

  const AlbumDetailScreen({
    super.key,
    required this.metadata,
    this.isOffline = false,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<PlexMetadata>? _tracks;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  PlexClient? _getClient() {
    return widget.isOffline ? null : context.getClientForMetadataOrNull(widget.metadata, isOffline: false);
  }

  Future<void> _loadTracks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.isOffline) {
        final downloadProvider = context.read<DownloadProvider>();
        final tracks = downloadProvider.getDownloadedTracksForAlbum(widget.metadata.ratingKey);
        tracks.sort((a, b) => (a.index ?? 0).compareTo(b.index ?? 0));
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      } else {
        final client = _getClient();
        if (client == null) {
          setState(() {
            _error = t.messages.errorLoadingAlbum;
            _isLoading = false;
          });
          return;
        }

        final children = await client.getChildren(widget.metadata.ratingKey);
        setState(() {
          _tracks = children.where((c) => c.type == 'track').toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      appLogger.e('Failed to load tracks', error: e);
      if (mounted) {
        setState(() {
          _error = t.messages.errorLoadingAlbum;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadAlbum() async {
    final client = _getClient();
    if (client == null) return;

    final downloadProvider = context.read<DownloadProvider>();
    try {
      final count = await downloadProvider.queueDownload(widget.metadata, client);
      if (mounted) {
        showSuccessSnackBar(context, t.downloads.tracksQueued(count: count));
      }
    } catch (e) {
      appLogger.e('Failed to queue album download', error: e);
      if (mounted) {
        showErrorSnackBar(context, e.toString());
      }
    }
  }

  Future<void> _downloadTrack(PlexMetadata track) async {
    final client = _getClient();
    if (client == null) return;

    final downloadProvider = context.read<DownloadProvider>();
    try {
      await downloadProvider.queueDownload(track.copyWith(serverId: widget.metadata.serverId), client);
      if (mounted) {
        showSuccessSnackBar(context, t.downloads.downloadQueued);
      }
    } catch (e) {
      appLogger.e('Failed to queue track download', error: e);
      if (mounted) {
        showErrorSnackBar(context, e.toString());
      }
    }
  }

  void _playTrack(PlexMetadata track, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MusicPlayerScreen(
          track: track,
          isOffline: widget.isOffline,
          playlist: _tracks,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artistName = widget.metadata.parentTitle ?? widget.metadata.grandparentTitle ?? '';
    final client = _getClient();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.metadata.title ?? '',
                style: const TextStyle(shadows: [Shadow(blurRadius: 4)]),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.metadata.thumb != null)
                    PlexOptimizedImage(
                      client: client,
                      imagePath: widget.metadata.thumb,
                      fit: BoxFit.cover,
                      fallbackIcon: Icons.album,
                    )
                  else
                    Container(color: theme.colorScheme.surfaceContainerHighest),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Artist name and download button
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (artistName.isNotEmpty)
                          Text(
                            artistName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (widget.metadata.year != null)
                          Text(
                            '${widget.metadata.year}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!widget.isOffline)
                    Consumer<DownloadProvider>(
                      builder: (context, dp, _) {
                        final progress = dp.getProgress(widget.metadata.globalKey);
                        if (progress != null && progress.status == DownloadStatus.completed) {
                          return const Icon(Icons.download_done, color: Colors.green);
                        }
                        return IconButton(
                          icon: const Icon(Symbols.download_rounded),
                          tooltip: t.music.downloadAlbum,
                          onPressed: _downloadAlbum,
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          // Tracks header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                t.music.tracks,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),

          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(child: Text(_error!)),
            )
          else if (_tracks == null || _tracks!.isEmpty)
            SliverFillRemaining(
              child: Center(child: Text(t.music.noTracks)),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks![index];
                  return _TrackListTile(
                    track: track,
                    isOffline: widget.isOffline,
                    onPlay: () => _playTrack(track, index),
                    onDownload: widget.isOffline ? null : () => _downloadTrack(track),
                    serverId: widget.metadata.serverId,
                  );
                },
                childCount: _tracks!.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackListTile extends StatelessWidget {
  final PlexMetadata track;
  final bool isOffline;
  final VoidCallback onPlay;
  final VoidCallback? onDownload;
  final String? serverId;

  const _TrackListTile({
    required this.track,
    required this.isOffline,
    required this.onPlay,
    this.onDownload,
    this.serverId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackNumber = track.index?.toString() ?? '';
    final duration = track.duration != null
        ? formatDurationTimestamp(Duration(milliseconds: track.duration!))
        : '';

    return Consumer<DownloadProvider>(
      builder: (context, dp, _) {
        final globalKey = track.globalKey;
        final progress = dp.getProgress(globalKey);
        final isDownloaded = progress?.status == DownloadStatus.completed;
        final isDownloading = progress?.status == DownloadStatus.downloading ||
            progress?.status == DownloadStatus.queued;

        return ListTile(
          leading: SizedBox(
            width: 32,
            child: Text(
              trackNumber,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          title: Text(
            track.title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(duration),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDownloaded)
                const Icon(Icons.download_done, size: 20, color: Colors.green),
              if (isDownloading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (!isOffline && !isDownloaded && !isDownloading && onDownload != null)
                IconButton(
                  icon: const Icon(Symbols.download_rounded, size: 20),
                  onPressed: onDownload,
                  tooltip: t.music.downloadTrack,
                ),
            ],
          ),
          onTap: onPlay,
        );
      },
    );
  }
}
