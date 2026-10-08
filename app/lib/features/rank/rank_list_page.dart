import 'package:flutter/material.dart';

import 'rank_boards_grid.dart';
export 'rank_hero.dart';

/// 全部榜单页（`/ranks`）。
///
/// 内容就是 [RankBoardsGrid]——探索发现「排行榜」Tab 用的也是它，
/// 两边不再各写一份取数 / 源解析 / 网格。
class RankListPage extends StatelessWidget {
  const RankListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('排行榜')),
      body: RankBoardsGrid(showSourceFilter: true),
    );
  }
}
