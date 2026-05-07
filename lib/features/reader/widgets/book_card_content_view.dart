import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../../../db/isar_db.dart';
import '../../../models/book_asset.dart';
import '../../../models/book_card.dart';
import '../../../services/book_asset_store.dart';

class BookCardContentView extends StatefulWidget {
  const BookCardContentView({
    super.key,
    required this.card,
    required this.style,
  });

  final BookCard card;
  final TextStyle? style;

  @override
  State<BookCardContentView> createState() => _BookCardContentViewState();
}

class _BookCardContentViewState extends State<BookCardContentView> {
  Future<Map<String, _ResolvedAsset>>? _assetsFuture;
  _CardBlocksDocument? _document;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(BookCardContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id ||
        oldWidget.card.blocksJson != widget.card.blocksJson) {
      _prepare();
    }
  }

  void _prepare() {
    _document = _CardBlocksDocument.tryParse(widget.card.blocksJson);
    final keys = _document?.assetKeys ?? const <String>[];
    _assetsFuture = keys.isEmpty
        ? null
        : _loadAssets(bookId: widget.card.bookId, assetKeys: keys);
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (document == null) {
      return PlainBookCardContentText(
        content: widget.card.content,
        style: widget.style,
      );
    }

    final future = _assetsFuture;
    if (future == null) {
      return _buildBlocks(context, document, const <String, _ResolvedAsset>{});
    }

    return FutureBuilder<Map<String, _ResolvedAsset>>(
      future: future,
      builder: (context, snapshot) {
        return _buildBlocks(
          context,
          document,
          snapshot.data ?? const <String, _ResolvedAsset>{},
          isLoadingAssets: snapshot.connectionState != ConnectionState.done,
        );
      },
    );
  }

  Widget _buildBlocks(
    BuildContext context,
    _CardBlocksDocument document,
    Map<String, _ResolvedAsset> assets, {
    bool isLoadingAssets = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < document.blocks.length; index += 1) ...[
          _blockWidget(
            context,
            document.blocks[index],
            assets,
            isLoadingAssets: isLoadingAssets,
          ),
          if (index < document.blocks.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _blockWidget(
    BuildContext context,
    _CardRenderBlock block,
    Map<String, _ResolvedAsset> assets, {
    required bool isLoadingAssets,
  }) {
    switch (block.type) {
      case _CardRenderBlockType.text:
        return PlainBookCardContentText(
          content: block.text,
          style: widget.style,
        );
      case _CardRenderBlockType.image:
        return _ImageBlock(
          asset: assets[block.assetKey],
          alt: block.alt,
          isLoading: isLoadingAssets,
        );
    }
  }

  Future<Map<String, _ResolvedAsset>> _loadAssets({
    required int bookId,
    required List<String> assetKeys,
  }) async {
    final isar = await IsarDb.instance.isar;
    final assets = await isar.bookAssets
        .filter()
        .bookIdEqualTo(bookId)
        .anyOf(assetKeys, (query, key) => query.assetKeyEqualTo(key))
        .findAll();

    final entries = await Future.wait(
      assets.map((asset) async {
        final file = await BookAssetStore.instance.resolveRelativeFile(
          asset.relativePath,
        );
        return MapEntry(
          asset.assetKey,
          _ResolvedAsset(asset: asset, file: file),
        );
      }),
    );

    return Map<String, _ResolvedAsset>.fromEntries(entries);
  }
}

class PlainBookCardContentText extends StatelessWidget {
  const PlainBookCardContentText({
    super.key,
    required this.content,
    required this.style,
  });

  final String content;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final paragraphs = content
        .split(RegExp(r'\n+'))
        .map((paragraph) => paragraph.trimRight())
        .where((paragraph) => paragraph.trim().isNotEmpty)
        .toList(growable: false);
    final textStyle = style?.copyWith(height: 1.5);

    if (paragraphs.isEmpty) {
      return Text('', style: textStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < paragraphs.length; index += 1) ...[
          Text(paragraphs[index], style: textStyle),
          if (index < paragraphs.length - 1) const SizedBox(height: 2),
        ],
      ],
    );
  }
}

class _ImageBlock extends StatelessWidget {
  const _ImageBlock({
    required this.asset,
    required this.alt,
    required this.isLoading,
  });

  final _ResolvedAsset? asset;
  final String alt;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final resolved = asset;
    if (resolved == null) {
      return _ImagePlaceholder(
        label: isLoading ? '图片加载中…' : (alt.isEmpty ? '图片未找到' : alt),
      );
    }

    final mimeType = resolved.asset.mimeType?.toLowerCase() ?? '';
    final path = resolved.file.path.toLowerCase();
    if (mimeType.contains('svg') || path.endsWith('.svg')) {
      return _ImagePlaceholder(label: alt.isEmpty ? '暂不支持 SVG 图片' : alt);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: Image.file(
          resolved.file,
          width: double.infinity,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _ImagePlaceholder(label: alt.isEmpty ? '图片无法显示' : alt);
          },
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 128),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ResolvedAsset {
  const _ResolvedAsset({required this.asset, required this.file});

  final BookAsset asset;
  final File file;
}

class _CardBlocksDocument {
  const _CardBlocksDocument({required this.blocks});

  final List<_CardRenderBlock> blocks;

  List<String> get assetKeys {
    return blocks
        .where((block) => block.type == _CardRenderBlockType.image)
        .map((block) => block.assetKey)
        .where((assetKey) => assetKey.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static _CardBlocksDocument? tryParse(String? blocksJson) {
    if (blocksJson == null || blocksJson.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(blocksJson);
      if (decoded is! Map<String, dynamic>) return null;
      final rawBlocks = decoded['blocks'];
      if (rawBlocks is! List) return null;

      final blocks = <_CardRenderBlock>[];
      for (final rawBlock in rawBlocks) {
        if (rawBlock is! Map) continue;
        final type = rawBlock['type'];
        if (type == 'text') {
          final text = rawBlock['text'];
          if (text is String && text.trim().isNotEmpty) {
            blocks.add(_CardRenderBlock.text(text));
          }
          continue;
        }
        if (type == 'image') {
          final assetKey = rawBlock['assetKey'];
          if (assetKey is! String || assetKey.trim().isEmpty) continue;
          final alt = rawBlock['alt'];
          blocks.add(
            _CardRenderBlock.image(
              assetKey: assetKey.trim(),
              alt: alt is String ? alt : '',
            ),
          );
        }
      }

      return blocks.isEmpty ? null : _CardBlocksDocument(blocks: blocks);
    } catch (_) {
      return null;
    }
  }
}

enum _CardRenderBlockType { text, image }

class _CardRenderBlock {
  const _CardRenderBlock.text(this.text)
    : type = _CardRenderBlockType.text,
      assetKey = '',
      alt = '';

  const _CardRenderBlock.image({required this.assetKey, required this.alt})
    : type = _CardRenderBlockType.image,
      text = '';

  final _CardRenderBlockType type;
  final String text;
  final String assetKey;
  final String alt;
}
