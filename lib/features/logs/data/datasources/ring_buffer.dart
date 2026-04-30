/// 固定容量的循环缓冲区，头部插入语义。
/// 新元素写入头部，满时自动淘汰最旧条目。
class RingBuffer<T> {
  final int capacity;
  late final List<T?> _buffer;
  int _head = -1;
  int _count = 0;

  RingBuffer(this.capacity) : _buffer = List.filled(capacity, null);

  int get length => _count;
  bool get isEmpty => _count == 0;

  /// 写入新元素（头部插入）
  void add(T item) {
    _head = (_head + 1) % capacity;
    _buffer[_head] = item;
    if (_count < capacity) _count++;
  }

  /// 按从新到旧的顺序获取第 [index] 个元素
  T get(int index) {
    final slot = (_head - index + capacity) % capacity;
    return _buffer[slot] as T;
  }

  /// 按条件查找并替换第一个匹配的元素
  /// 从最新到最旧遍历，匹配时原地替换
  /// 返回 true 表示找到并更新
  bool updateWhere(bool Function(T item) test, T Function(T old) updater) {
    for (int i = 0; i < _count; i++) {
      final slot = (_head - i + capacity) % capacity;
      final item = _buffer[slot];
      if (item != null && test(item)) {
        _buffer[slot] = updater(item);
        return true;
      }
    }
    return false;
  }

  void clear() {
    _buffer.fillRange(0, capacity, null);
    _head = -1;
    _count = 0;
  }
}
