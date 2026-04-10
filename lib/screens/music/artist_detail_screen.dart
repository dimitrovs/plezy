import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plex_metadata.dart';
import '../../providers/download_provider.dart';
import '../../services/plex_client.dart';
import '../../utils/app_logger.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/plex_optimized_image.dart';
import '../../i18n/strings.g.dart';
import 'album_detail_screen.dart';

/// Screen showing an artist's albums.
class ArtistDetailScreen extends StatefulWidget {
  final PlexMetadata metadata;
  final bool isOffline;

  const ArtistDetailScreen({
    super.key,
    required this.metadata,
    this.isOffline = false,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  List<PlexMetadata>? _albums;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  PlexClient? _getClient() {
    return widget.isOffline ? null : context.getClientForMetadataOrNull(widget.metadata, isOffline: false);
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.isOffline) {
        final downloadProvider = context.read<DownloadProvider>();
        final tracks = downloadProvider.getDownloadedTracksForArtist(widget.metadata.ratingKey);

        // Group tracks by album
        final Map<String, PlexMetadata> albumMap = {};
        for (final track in tracks) {
          final albumKey = track.parentRatingKey;
          if (albumKey != null && !albumMap.containsKey(albumKey)) {
            final albumGlobalKey = '${track.serverId}:$albumKey';
            final storedAlbum = downloadProvider.getMetadata(albumGlobalKey);
            albumMap[albumKey] = storedAlbum ?? PlexMetadata(
              ratingKey: albumKey,
              key: '/library/metadata/$albumKey',
              type: 'album',
              title: track.parentTitle ?? 'Unknown Album',
              thumb: track.parentThumb,
              parentTitle: widget.metadata.title,
              parentRatingKey: widget.metadata.ratingKey,
              serverId: track.serverId,
            );
          }
        }

        setState(() {
          _albums = albumMap.values.toList();
          _isLoading = false;
        });
      } else {
        final client = _getClient();
        if (client == null) {
          setState(() {
            _error = t.messages.errorLoadingArtist;
            _isLoading = false;
          });
          return;
        }

        final children = await client.getChildren(widget.metadata.ratingKey);
        setState(() {
          _albums = children.where((c) => c.type == 'album').toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      appLogger.e('Failed to load albums', error: e);
      if (mounted) {
        setState(() {
          _error = t.messages.errorLoadingArtist;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = _getClient();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.metadata.title ?? '',
                style: const TextStyle(shadows: [Shadow(blurRadius: 4)]),
              ),
              background: widget.metadata.art != null
                  ? PlexOptimizedImage(
                      client: client,
                      imagePath: widget.metadata.art,
                      fit: BoxFit.cover,
                      fallbackIcon: Icons.person,
                    )
                  : Container(color: theme.colorScheme.surfaceContainerHighest),
            ),
          ),

          if (widget.metadata.summary != null && widget.metadata.summary!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.metadata.summary!,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                t.music.albums,
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
          else if (_albums == null || _albums!.isEmpty)
            SliverFillRemaining(
              child: Center(child: Text(t.music.noTracks)),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final album = _albums![index];
                  return _AlbumListTile(
                    album: album,
                    isOffline: widget.isOffline,
                    client: client,
                    serverId: widget.metadata.serverId,
                  );
                },
                childCount: _albums!.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _AlbumListTile extends StatelessWidget {
  final PlexMetadata album;
  final bool isOffline;
  final PlexClient? client;
  final String? serverId;

  const _AlbumListTile({
    required this.album,
    required this.isOffline,
    this.client,
    this.serverId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = album.year != null ? ' (${album.year})' : '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SizedBox(
        width: 56,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: album.thumb != null
              ? PlexOptimizedImage(
                  client: client,
                  imagePath: album.thumb,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  fallbackIcon: Icons.album,
                )
              : Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.album, color: theme.colorScheme.onSurfaceVariant),
                ),
        ),
      ),
      title: Text('${album.title ?? ""}$year'),
      subtitle: album.leafCount != null ? Text('${album.leafCount} ${t.music.tracks.toLowerCase()}') : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumDetailScreen(
              metadata: album.copyWith(serverId: serverId),
              isOffline: isOffline,
            ),
          ),
        );
      },
    );
  }
}
