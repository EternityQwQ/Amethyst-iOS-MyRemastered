// AmethystInstallerServiceTests —— P6b-1 纯函数对象化的灰盒契约（Apple XCTest）。
// 被测真实现：Natives/UI/Download/DownloadInstallerService.m（如实编进 bundle）。
// 桩面复用 AMEEngineStubs（getPrefObject/localize/customNSLog）。
// 覆盖（全部 hermetic，不碰网络）：缺文件→NO、空id→NO、JSON已存在→YES短路、JSON存在即跳过下载。
@import XCTest;
#import "DownloadInstallerService.h"

@interface AmethystInstallerServiceTests : XCTestCase
@property (nonatomic, copy) NSString *tmpGameDir;
@property (nonatomic, copy) NSString *savedGameDir;
@property (nonatomic, copy) NSString *savedHome;
@end

@implementation AmethystInstallerServiceTests

- (void)setUp {
    [super setUp];
    const char *g = getenv("POJAV_GAME_DIR");
    self.savedGameDir = g ? @(g) : nil;
    const char *h = getenv("POJAV_HOME");
    self.savedHome = h ? @(h) : nil;
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];
    self.tmpGameDir = tmp;
    setenv("POJAV_GAME_DIR", tmp.UTF8String, 1);
    setenv("POJAV_HOME", tmp.UTF8String, 1);
}

- (void)tearDown {
    if (self.savedGameDir) setenv("POJAV_GAME_DIR", self.savedGameDir.UTF8String, 1);
    else unsetenv("POJAV_GAME_DIR");
    if (self.savedHome) setenv("POJAV_HOME", self.savedHome.UTF8String, 1);
    else unsetenv("POJAV_HOME");
    [[NSFileManager defaultManager] removeItemAtPath:self.tmpGameDir error:nil];
    [super tearDown];
}

- (NSString *)jsonPathForVersion:(NSString *)versionId {
    NSString *dir = [self.tmpGameDir stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"versions/%@", versionId]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", versionId]];
}

// 缺文件 → 未安装
- (void)testIsVanillaVersionInstalled_MissingReturnsNO {
    XCTAssertFalse([DownloadInstallerService isVanillaVersionInstalled:@"1.21"]);
}

// 空 id → 未安装（不碰文件系统边界）
- (void)testIsVanillaVersionInstalled_EmptyReturnsNO {
    XCTAssertFalse([DownloadInstallerService isVanillaVersionInstalled:@""]);
    XCTAssertFalse([DownloadInstallerService isVanillaVersionInstalled:nil]);
}

// JSON 存在 → 已安装
- (void)testIsVanillaVersionInstalled_ExistingJSONReturnsYES {
    NSString *p = [self jsonPathForVersion:@"1.21"];
    [@"{}" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    XCTAssertTrue([DownloadInstallerService isVanillaVersionInstalled:@"1.21"]);
}

// JSON 已存在 → 直接 YES，不发起网络（hermetic：CI 无网也绿）
- (void)testEnsureVanillaJSONExists_ShortCircuitsWhenPresent {
    NSString *p = [self jsonPathForVersion:@"1.20.1"];
    [@"{}" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    XCTestExpectation *exp = [self expectationWithDescription:@"short-circuit"];
    [DownloadInstallerService ensureVanillaVersionJSONExists:@"1.20.1" completion:^(BOOL success) {
        XCTAssertTrue(success);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
}

@end
