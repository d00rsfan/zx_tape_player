import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

import '../../../utils/extensions.dart';

class BlockBrowser extends StatelessWidget {
  final List<TapeBlockInfo> blocks;
  final Duration currentPosition;
  final ValueChanged<int> onBlockTap;

  const BlockBrowser({
    super.key,
    required this.blocks,
    required this.currentPosition,
    required this.onBlockTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HexColor('#3B4E63'),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8.0),
          Container(
            width: 40.0,
            height: 4.0,
            decoration: BoxDecoration(
              color: HexColor('#546B7F'),
              borderRadius: BorderRadius.circular(2.0),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Text(
              tr('block_browser'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: blocks.length,
              padding: const EdgeInsets.only(bottom: 16.0),
              itemBuilder: (context, index) {
                final block = blocks[index];
                final isCurrent = _isCurrentBlock(block);
                return _buildBlockRow(block, isCurrent);
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _isCurrentBlock(TapeBlockInfo block) {
    final blockEnd = block.timeOffset + block.duration;
    return currentPosition >= block.timeOffset && currentPosition < blockEnd;
  }

  Widget _buildBlockRow(TapeBlockInfo block, bool isCurrent) {
    return InkWell(
      onTap: () => onBlockTap(block.index),
      child: Container(
        color: isCurrent ? HexColor('#4A5D72') : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          children: [
            SizedBox(
              width: 32.0,
              child: Text(
                '${block.index + 1}',
                style: TextStyle(
                    color: HexColor('#B1B8C1'),
                    fontSize: 12.0),
              ),
            ),
            Icon(
              _iconForType(block.typeName),
              color: isCurrent ? Colors.white : HexColor('#B1B8C1'),
              size: 18.0,
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _blockLabel(block),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.0,
                        fontWeight:
                            block.isHeader ? FontWeight.w600 : FontWeight.normal),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (block.dataLength != null)
                    Text(
                      '${block.dataLength} ${tr('block_bytes')}',
                      style: TextStyle(
                          color: HexColor('#B1B8C1'), fontSize: 11.0),
                    ),
                ],
              ),
            ),
            Text(
              _formatDuration(block.timeOffset),
              style: TextStyle(
                  color: HexColor('#B1B8C1'),
                  fontSize: 12.0,
                  fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  String _blockLabel(TapeBlockInfo block) {
    if (block.title != null && block.title!.isNotEmpty) {
      return '${block.typeName}: ${block.title}';
    }
    return block.typeName;
  }

  IconData _iconForType(String typeName) {
    switch (typeName) {
      case 'Program':
        return Icons.code_rounded;
      case 'Code':
        return Icons.memory_rounded;
      case 'Number Array':
      case 'Character Array':
        return Icons.grid_on_rounded;
      case 'Data':
        return Icons.storage_rounded;
      case 'Pause':
        return Icons.pause_rounded;
      case 'Tone':
      case 'Pulses':
        return Icons.graphic_eq_rounded;
      default:
        return Icons.album_rounded;
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
