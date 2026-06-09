import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/api_config.dart';
import '../../core/network/reconstruction_service.dart';
import '../../core/router/route_config.dart';
import '../../core/services/task_thumbnail_service.dart';
import '../../core/state/language_state.dart';

final Map<String, Future<File?>> _previewDownloadCache = {};

class RecommendationPage extends StatefulWidget {
  const RecommendationPage({super.key});

  @override
  State<RecommendationPage> createState() => _RecommendationPageState();
}

class _RecommendationPageState extends State<RecommendationPage> {
  static const int _pageSize = 10;

  final ReconstructionService _service = ReconstructionService();
  final ScrollController _scrollController = ScrollController();
  final List<PublicReconstructionTask> _tasks = [];

  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  int _skip = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_loadFirstPage());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 480) {
      unawaited(_loadNextPage());
    }
  }

  Future<void> _loadFirstPage() async {
    debugPrint('[DiscoverPage] trigger load first page pageSize=$_pageSize');
    setState(() {
      _isInitialLoading = true;
      _isLoadingMore = false;
      _hasMore = true;
      _errorMessage = null;
      _skip = 0;
      _tasks.clear();
    });

    final page = await _service.discoverPublicTasks(skip: 0, limit: _pageSize);
    if (!mounted) return;
    debugPrint(
      '[DiscoverPage] result first page items=${page.items.length} '
      'total=${page.total} hasNext=${page.hasNext}',
    );

    setState(() {
      _tasks.addAll(page.items);
      _skip = _tasks.length;
      _hasMore = page.hasNext ??
          (page.items.length >= _pageSize &&
              (page.total <= 0 || _tasks.length < page.total));
      _isInitialLoading = false;
      if (_tasks.isEmpty) {
        debugPrint('[DiscoverPage] result empty after first page');
        _errorMessage = 'discover.empty';
      }
    });
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    debugPrint('[DiscoverPage] trigger load next skip=$_skip pageSize=$_pageSize');
    setState(() => _isLoadingMore = true);

    final page = await _service.discoverPublicTasks(
      skip: _skip,
      limit: _pageSize,
    );
    if (!mounted) return;
    debugPrint(
      '[DiscoverPage] result next page items=${page.items.length} '
      'total=${page.total} hasNext=${page.hasNext}',
    );

    setState(() {
      _tasks.addAll(page.items);
      _skip = _tasks.length;
      _hasMore = page.hasNext ??
          (page.items.length >= _pageSize &&
              (page.total <= 0 || _tasks.length < page.total));
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          context.tr('discover.title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF00C6FF),
          backgroundColor: const Color(0xFF071027),
          onRefresh: _loadFirstPage,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    debugPrint(
      '[DiscoverPage] build loading=$_isInitialLoading '
      'tasks=${_tasks.length} hasMore=$_hasMore error=$_errorMessage',
    );
    if (_isInitialLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00C6FF)),
      );
    }

    if (_tasks.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 180),
          Icon(
            Icons.public_off_outlined,
            color: Colors.white.withValues(alpha: 0.42),
            size: 48,
          ),
          const SizedBox(height: 14),
          Text(
            context.tr(_errorMessage ?? 'discover.empty'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 15,
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childCount: _tasks.length,
            itemBuilder: (context, index) {
              final task = _tasks[index];
              return _PublicTaskCard(
                task: task,
                imageHeight: _heightForIndex(index),
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _isLoadingMore
                ? const Padding(
                    key: ValueKey('loading_more'),
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00C6FF),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(key: ValueKey('idle_more'), height: 18),
          ),
        ),
      ],
    );
  }

  double _heightForIndex(int index) {
    const heights = [220.0, 172.0, 248.0, 196.0, 232.0, 184.0];
    return heights[index % heights.length];
  }
}

class _PublicTaskCard extends StatefulWidget {
  final PublicReconstructionTask task;
  final double imageHeight;

  const _PublicTaskCard({
    required this.task,
    required this.imageHeight,
  });

  @override
  State<_PublicTaskCard> createState() => _PublicTaskCardState();
}

class _PublicTaskCardState extends State<_PublicTaskCard> {
  final TaskThumbnailService _thumbnailService = TaskThumbnailService.instance;

  @override
  Widget build(BuildContext context) {
    final canOpen = widget.task.taskId.trim().isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canOpen ? _openTaskDetail : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      _buildThumbnail(),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _PublicBadge(
                          label: context.tr('discover.publicBadge'),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    child: _buildOwnerInfo(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerInfo(BuildContext context) {
    final displayName = widget.task.ownerDisplayName.trim().isNotEmpty
        ? widget.task.ownerDisplayName.trim()
        : (widget.task.userId.trim().isEmpty ? 'unknown' : widget.task.userId);
    final userId = widget.task.userId.trim();
    final avatarText = displayName.isEmpty
        ? '?'
        : displayName.substring(0, 1).toUpperCase();

    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF00C6FF).withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF00C6FF).withValues(alpha: 0.28),
            ),
          ),
          child: Text(
            avatarText,
            style: const TextStyle(
              color: Color(0xFF00C6FF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('discover.owner'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.46),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                userId.isEmpty ? displayName : '$displayName | ID $userId',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.chevron_right,
          size: 18,
          color: Colors.white.withValues(alpha: 0.44),
        ),
      ],
    );
  }

  void _openTaskDetail() {
    final taskId = widget.task.taskId.trim();
    if (taskId.isEmpty) return;
    debugPrint(
      '[DiscoverPage] trigger open task detail taskId=$taskId '
      'userId=${widget.task.userId}',
    );
    context.push('$taskTabPath/$taskDetailPath/${Uri.encodeComponent(taskId)}');
  }

  Widget _buildThumbnail() {
    if (widget.task.thumbnailUrl.trim().isNotEmpty) {
      debugPrint(
        '[DiscoverPage] thumbnail network taskId=${widget.task.taskId} '
        'url=${widget.task.thumbnailUrl}',
      );
      return Image.network(
        _resolveImageUrl(widget.task.thumbnailUrl),
        height: widget.imageHeight,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(
          Icons.image_not_supported_outlined,
        ),
      );
    }

    final hasFileCandidates =
        widget.task.previewFileId != null ||
        widget.task.previewFileIds.isNotEmpty ||
        widget.task.inputFileIds.isNotEmpty ||
        widget.task.taskId.trim().isNotEmpty;
    if (!hasFileCandidates) {
      debugPrint(
        '[DiscoverPage] thumbnail missing taskId=${widget.task.taskId} '
        'userId=${widget.task.userId}',
      );
      return _buildImagePlaceholder(Icons.image_outlined);
    }

    debugPrint(
      '[DiscoverPage] thumbnail download taskId=${widget.task.taskId} '
      'previewFileId=${widget.task.previewFileId} '
      'previewIds=${widget.task.previewFileIds.length} '
      'inputFileIds=${widget.task.inputFileIds.length}',
    );
    final cacheKey = widget.task.taskId.trim().isNotEmpty
        ? widget.task.taskId
        : widget.task.previewFileId ?? widget.task.inputFileIds.join(',');
    final future = _previewDownloadCache.putIfAbsent(
      cacheKey,
      () => _thumbnailService.resolveForPublicTask(widget.task),
    );
    return FutureBuilder<File?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildLoadingThumbnail();
        }
        final file = snapshot.data;
        if (file == null || !file.existsSync()) {
          return _buildImagePlaceholder(Icons.image_not_supported_outlined);
        }
        return Image.file(
          file,
          height: widget.imageHeight,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildImagePlaceholder(Icons.image_not_supported_outlined),
        );
      },
    );
  }

  Widget _buildLoadingThumbnail() {
    return Container(
      height: widget.imageHeight,
      color: Colors.white.withValues(alpha: 0.05),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF00C6FF),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(IconData icon) {
    return Container(
      height: widget.imageHeight,
      color: Colors.white.withValues(alpha: 0.05),
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: Colors.white.withValues(alpha: 0.35),
      ),
    );
  }

  String _resolveImageUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return trimmed;
    if (trimmed.startsWith('/')) {
      final root = Uri.parse('${ApiPaths.baseUrl}:${ApiPaths.port}');
      return root.resolve(trimmed).toString();
    }
    final base = Uri.parse(
      '${ApiPaths.baseUrl}:${ApiPaths.port}${ApiPaths.publicHead}',
    );
    return base.resolve(trimmed).toString();
  }
}

class _PublicBadge extends StatelessWidget {
  final String label;

  const _PublicBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.public, color: Color(0xFF00C6FF), size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
