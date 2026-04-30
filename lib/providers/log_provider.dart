import 'package:flutter/material.dart';
import 'package:llm_proxy/models/proxy_log.dart';

/// 固定容量的循环 buffer，新日志写入头部，满时自动淘汰最旧条目。
/// 通过 Map 维护 ID → 槽位映射，支持 O(1) 查找更新。
class _RingBuffer {
  final int capacity;
  late final List<ProxyLog?> _buffer;
  // head 指向最新写入的槽位
  int _head = -1;
  int _count = 0;
  // ID → buffer 槽位索引
  final Map<String, int> _idSlotMap = {};

  _RingBuffer(this.capacity) : _buffer = List.filled(capacity, null);

  int get length => _count;
  bool get isEmpty => _count == 0;

  /// 写入新日志（头部插入语义）
  void add(ProxyLog log) {
    _head = (_head + 1) % capacity;
    // 如果该槽位有旧数据，移除其 ID 映射
    final old = _buffer[_head];
    if (old != null) {
      _idSlotMap.remove(old.id);
    }
    _buffer[_head] = log;
    _idSlotMap[log.id] = _head;
    if (_count < capacity) _count++;
  }

  /// O(1) 按 ID 更新
  void update(String id, ProxyLog updatedLog) {
    final slot = _idSlotMap[id];
    if (slot == null) return;
    _buffer[slot] = updatedLog;
    // ID 不变，无需更新映射
  }

  /// 按从新到旧的顺序获取第 [index] 条日志
  ProxyLog operator [](int index) {
    assert(index >= 0 && index < _count);
    final slot = (_head - index + capacity) % capacity;
    return _buffer[slot]!;
  }

  void clear() {
    _buffer.fillRange(0, capacity, null);
    _idSlotMap.clear();
    _head = -1;
    _count = 0;
  }

  bool containsId(String id) => _idSlotMap.containsKey(id);
}

class LogProvider extends ChangeNotifier {
  static const int maxLogs = 500;
  final _RingBuffer _ring = _RingBuffer(maxLogs);

  int get logCount => _ring.length;

  /// 按索引访问（0 = 最新），供 ListView.builder 使用
  ProxyLog getLog(int index) => _ring[index];

  void addLog(ProxyLog log) {
    _ring.add(log);
    notifyListeners();
  }

  /// 按 ID 更新已有日志
  /// [silent] 为 true 时不触发 UI 刷新，适用于中间状态的渐进更新
  void updateLog(ProxyLog updatedLog, {bool silent = false}) {
    if (!_ring.containsId(updatedLog.id)) return;
    _ring.update(updatedLog.id, updatedLog);
    if (!silent) {
      notifyListeners();
    }
  }

  void clearLogs() {
    _ring.clear();
    notifyListeners();
  }
}
