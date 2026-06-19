/// 我们的家·长聊记忆：窗口计算（纯函数，无副作用，便于单测）。
///
/// 返回此刻应被蒸馏归档的消息块的绝对下标区间 [start, end)，无可归档时返回 null。
/// keep      = 始终保留的最近消息条数；
/// trigger   = 总条数超过它时才触发蒸馏；
/// step      = trigger - keep，窗口起点只按 step 的整数倍前移（避免每来一条就蒸馏）；
/// digestedCount = 已处理的高水位线（绝对计数）。
({int start, int end})? ourHomeOverflowRange({
  required int n, // 消息总条数
  required int keep,
  required int trigger,
  required int digestedCount,
}) {
  if (n <= trigger) return null;
  final step = (trigger - keep) < 1 ? 1 : (trigger - keep);
  final newStart = ((n - keep) ~/ step) * step; // 绝对窗口起点
  if (newStart <= digestedCount) return null;
  return (start: digestedCount, end: newStart);
}
