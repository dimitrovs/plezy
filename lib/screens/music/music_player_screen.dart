import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../models/plex_metadata.dart';
import '../../models/download_models.dart';
import '../../mpv/mpv.dart';
import '../../providers/download_provider.dart';
import '../../services/plex_client.dart';
import '../../utils/app_logger.dart';
import '../../utils/formatters.dart';
import '../../utils/provider_extensions.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/plex_optimized_image.dart';
import '../../i18n/strings.g.dart';

/// A screen for playing music tracks with controls, queue view, and download support.
class MusicPlayerScreen extends StatefulWidget {
  final PlexMetadata track;
  final bool isOffline;
  final List<PlexMetadata>? playlist;
  final int initialIndex;

  const MusicPlayerScreen({
    super.key,
    required this.track,
    this.isOffline = false,
    this.playlist,
    this.initialIndex = 0,
  });

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  Player? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = true;
  String? _error;

  late PlexMetadata _currentTrack;
  late List<PlexMetadata> _playlist;
  late int _currentIndex;

  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;

  @override
  void initState() {
    super.initState();
    _currentTrack = widget.track;
    _playlist = widget.playlist ?? [widget.track];
    _currentIndex = widget.initialIndex;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _player = Player();

      _positionSub = _player!.streams.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _durationSub = _player!.streams.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });
      _playingSub = _player!.streams.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });
      _completedSub = _player!.streams.completed.listen((completed) {
        if (completed) _playNext();
      });

      await _loadTrack(_currentTrack);
    } catch (e) {
      appLogger.e('Failed to initialize music player', error: e);
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadTrack(PlexMetadata track) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentTrack = track;
    });

    try {
      String? mediaUrl;

      if (widget.isOffline) {
        final downloadProvider = context.read<DownloadProvider>();
        mediaUrl = await downloadProvider.getAudioFilePath(track.globalKey);
        if (mediaUrl != null && !mediaUrl.contains('://')) {
          mediaUrl = 'file://$mediaUrl';
        }
      } else {
        final client = context.getClientForMetadataOrNull(track, isOffline: false);
        if (client != null) {
          final playbackData = await client.getVideoPlaybackData(track.ratingKey);
          mediaUrl = playbackData.videoUrl;
        }
      }

      if (mediaUrl == null) {
        setState(() {
          _error = 'Could not get audio URL';
          _isLoading = false;
        });
        return;
      }

      await _player!.open(Media(mediaUrl));
      setState(() => _isLoading = false);
    } catch (e) {
      appLogger.e('Failed to load track', error: e);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _playNext() {
    if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
      _loadTrack(_playlist[_currentIndex]);
    }
  }

  void _playPrevious() {
    if (_position.inSeconds > 3) {
      _player?.seek(Duration.zero);
    } else if (_currentIndex > 0) {
      _currentIndex--;
      _loadTrack(_playlist[_currentIndex]);
    }
  }

  void _playTrackAtIndex(int index) {
    if (index >= 0 && index < _playlist.length) {
      _currentIndex = index;
      _loadTrack(_playlist[index]);
    }
  }

  void _togglePlayPause() {
    _player?.playOrPause();
  }

  PlexClient? _getClient() {
    return widget.isOffline ? null : context.getClientForMetadataOrNull(_currentTrack, isOffline: false);
  }

  Future<void> _downloadCurrentTrack() async {
    final client = _getClient();
    if (client == null) return;

    final downloadProvider = context.read<DownloadProvider>();
    try {
      await downloadProvider.queueDownload(
        _currentTrack.copyWith(serverId: _currentTrack.serverId),
        client,
      );
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

  void _showQueue() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _QueueSheet(
          playlist: _playlist,
          currentIndex: _currentIndex,
          isOffline: widget.isOffline,
          onTrackTap: (index) {
            Navigator.pop(context);
            _playTrackAtIndex(index);
          },
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final albumTitle = _currentTrack.parentTitle ?? '';
    final artistTitle = _currentTrack.grandparentTitle ?? '';
    final client = _getClient();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.music.nowPlaying),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!widget.isOffline)
            Consumer<DownloadProvider>(
              builder: (context, dp, _) {
                final progress = dp.getProgress(_currentTrack.globalKey);
                if (progress != null && progress.status == DownloadStatus.completed) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.download_done, color: Colors.green),
                  );
                }
                if (progress != null && (progress.status == DownloadStatus.downloading || progress.status == DownloadStatus.queued)) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return IconButton(
                  icon: const Icon(Symbols.download_rounded),
                  tooltip: t.music.downloadTrack,
                  onPressed: _downloadCurrentTrack,
                );
              },
            ),
          if (_playlist.length > 1)
            IconButton(
              icon: const Icon(Symbols.queue_music_rounded),
              tooltip: t.music.tracks,
              onPressed: _showQueue,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Album art
            Expanded(
              flex: 3,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _currentTrack.parentThumb != null || _currentTrack.thumb != null
                          ? PlexOptimizedImage(
                              client: client,
                              imagePath: _currentTrack.parentThumb ?? _currentTrack.thumb,
                              fit: BoxFit.cover,
                              fallbackIcon: Icons.album,
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.album,
                                size: 80,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),

            // Track info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                children: [
                  Text(
                    _currentTrack.title ?? '',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    artistTitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (albumTitle.isNotEmpty)
                    Text(
                      albumTitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),

            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: _duration.inMilliseconds > 0
                          ? _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble())
                          : 0,
                      max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1,
                      onChanged: (value) {
                        _player?.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatDurationTimestamp(_position),
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          formatDurationTimestamp(_duration),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Controls
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 36,
                    onPressed: _playlist.length > 1 ? _playPrevious : null,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  const SizedBox(width: 16),
                  if (_isLoading)
                    const SizedBox(
                      width: 64,
                      height: 64,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    IconButton(
                      iconSize: 64,
                      onPressed: _togglePlayPause,
                      icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    ),
                  const SizedBox(width: 16),
                  IconButton(
                    iconSize: 36,
                    onPressed: _currentIndex < _playlist.length - 1 ? _playNext : null,
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet showing the play queue with download status for each track.
class _QueueSheet extends StatelessWidget {
  final List<PlexMetadata> playlist;
  final int currentIndex;
  final bool isOffline;
  final void Function(int index) onTrackTap;
  final ScrollController scrollController;

  const _QueueSheet({
    required this.playlist,
    required this.currentIndex,
    required this.isOffline,
    required this.onTrackTap,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Handle bar
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                t.music.tracks,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                '${currentIndex + 1} / ${playlist.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: playlist.length,
            itemBuilder: (context, index) {
              final track = playlist[index];
              final isCurrent = index == currentIndex;
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
                      child: isCurrent
                          ? Icon(
                              Symbols.play_arrow_rounded,
                              color: theme.colorScheme.primary,
                              fill: 1,
                            )
                          : Text(
                              '${index + 1}',
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
                      style: isCurrent
                          ? TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )
                          : null,
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
                      ],
                    ),
                    selected: isCurrent,
                    onTap: () => onTrackTap(index),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
