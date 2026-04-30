/// 应用级失败抽象类
sealed class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => message;
}

/// 本地数据源错误
class LocalDataSourceFailure extends Failure {
  const LocalDataSourceFailure(super.message);
}

/// 代理服务器错误
class ProxyServerFailure extends Failure {
  const ProxyServerFailure(super.message);
}
