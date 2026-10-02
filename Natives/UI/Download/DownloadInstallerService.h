// DownloadInstallerService.h —— 原版预装纯函数（P6b-1 从 InstallerCore 分类逐字搬移，零行为变更）。
//
// 搬移标准：方法体零 self 引用（仅 getenv/NSFileManager/NSURLSession/NSLog），
// 与 VC 状态（KVO/downloadTask/alert）无纠缠，可安全对象化。
// 有状态的 ensureVanillaInstalled:/startVersionDownload:（KVO 状态机）仍留 VC，见 P6b 纪要。
#import <Foundation/Foundation.h>

@interface DownloadInstallerService : NSObject

/// 检测指定原版版本是否已安装（versions/{versionId}/{versionId}.json 存在即视为已安装）。
+ (BOOL)isVanillaVersionInstalled:(NSString *)versionId;

/// 确保原版版本的 version JSON 已存在（缺失时从 Mojang/BMCLAPI 下载，仅 JSON 不含 client.jar）。
+ (void)ensureVanillaVersionJSONExists:(NSString *)versionId completion:(void (^)(BOOL success))completion;

@end
