/// 图片文件仓库：把照片落到应用目录，避免继续往 Hive 塞 base64。
///
/// Web 没有文件系统，走 stub（available=false），调用方需判断。
export 'image_store_stub.dart' if (dart.library.io) 'image_store_io.dart';
