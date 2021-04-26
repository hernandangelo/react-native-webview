/**
 * Copyright (c) 2015-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RNCWebViewManager.h"

#import <React/RCTUIManager.h>
#import <React/RCTDefines.h>
#import "RNCWebView.h"
#import "RNCWKProcessPoolManager.h"

@interface RNCWebViewManager () <RNCWebViewDelegate>
@end

static NSString * const NOT_AVAILABLE_ERROR_MESSAGE = @"WebKit/WebKit-Components are only available with iOS11 and higher!";
static NSString * const INVALID_URL_MISSING_HTTP = @"Invalid URL: It may be missing a protocol (ex. http:// or https://).";
static NSString * const INVALID_DOMAINS = @"Cookie URL host %@ and domain %@ mismatched. The cookie won't set correctly.";

static inline BOOL isEmpty(id value)
{
    return value == nil
        || ([value respondsToSelector:@selector(length)] && [(NSData *)value length] == 0)
        || ([value respondsToSelector:@selector(count)] && [(NSArray *)value count] == 0);
}


@implementation RCTConvert (WKWebView)
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000 /* iOS 13 */
RCT_ENUM_CONVERTER(WKContentMode, (@{
    @"recommended": @(WKContentModeRecommended),
    @"mobile": @(WKContentModeMobile),
    @"desktop": @(WKContentModeDesktop),
}), WKContentModeRecommended, integerValue)
#endif
@end

@implementation RNCWebViewManager
{
  NSConditionLock *_shouldStartLoadLock;
  BOOL _shouldStartLoad;
}

RCT_EXPORT_MODULE()

#if !TARGET_OS_OSX
- (UIView *)view
#else
- (RCTUIView *)view
#endif // !TARGET_OS_OSX
{
  RNCWebView *webView = [RNCWebView new];
  webView.delegate = self;
  return webView;
}

RCT_EXPORT_VIEW_PROPERTY(source, NSDictionary)
RCT_EXPORT_VIEW_PROPERTY(onFileDownload, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onLoadingStart, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onLoadingFinish, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onLoadingError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onLoadingProgress, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onHttpError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onShouldStartLoadWithRequest, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onContentProcessDidTerminate, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(injectedJavaScript, NSString)
RCT_EXPORT_VIEW_PROPERTY(injectedJavaScriptBeforeContentLoaded, NSString)
RCT_EXPORT_VIEW_PROPERTY(injectedJavaScriptForMainFrameOnly, BOOL)
RCT_EXPORT_VIEW_PROPERTY(injectedJavaScriptBeforeContentLoadedForMainFrameOnly, BOOL)
RCT_EXPORT_VIEW_PROPERTY(javaScriptEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(javaScriptCanOpenWindowsAutomatically, BOOL)
RCT_EXPORT_VIEW_PROPERTY(allowFileAccessFromFileURLs, BOOL)
RCT_EXPORT_VIEW_PROPERTY(allowUniversalAccessFromFileURLs, BOOL)
RCT_EXPORT_VIEW_PROPERTY(allowsInlineMediaPlayback, BOOL)
RCT_EXPORT_VIEW_PROPERTY(mediaPlaybackRequiresUserAction, BOOL)
#if WEBKIT_IOS_10_APIS_AVAILABLE
RCT_EXPORT_VIEW_PROPERTY(dataDetectorTypes, WKDataDetectorTypes)
#endif
RCT_EXPORT_VIEW_PROPERTY(contentInset, UIEdgeInsets)
RCT_EXPORT_VIEW_PROPERTY(automaticallyAdjustContentInsets, BOOL)
RCT_EXPORT_VIEW_PROPERTY(autoManageStatusBarEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(hideKeyboardAccessoryView, BOOL)
RCT_EXPORT_VIEW_PROPERTY(allowsBackForwardNavigationGestures, BOOL)
RCT_EXPORT_VIEW_PROPERTY(incognito, BOOL)
RCT_EXPORT_VIEW_PROPERTY(pagingEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(userAgent, NSString)
RCT_EXPORT_VIEW_PROPERTY(applicationNameForUserAgent, NSString)
RCT_EXPORT_VIEW_PROPERTY(cacheEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(allowsLinkPreview, BOOL)
RCT_EXPORT_VIEW_PROPERTY(allowingReadAccessToURL, NSString)

#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000 /* __IPHONE_11_0 */
RCT_EXPORT_VIEW_PROPERTY(contentInsetAdjustmentBehavior, UIScrollViewContentInsetAdjustmentBehavior)
#endif
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000 /* __IPHONE_13_0 */
RCT_EXPORT_VIEW_PROPERTY(automaticallyAdjustsScrollIndicatorInsets, BOOL)
#endif

#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000 /* iOS 13 */
RCT_EXPORT_VIEW_PROPERTY(contentMode, WKContentMode)
#endif

#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000 /* iOS 14 */
RCT_EXPORT_VIEW_PROPERTY(limitsNavigationsToAppBoundDomains, BOOL)
#endif

/**
 * Expose methods to enable messaging the webview.
 */
RCT_EXPORT_VIEW_PROPERTY(messagingEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(onMessage, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onScroll, RCTDirectEventBlock)

RCT_EXPORT_METHOD(postMessage:(nonnull NSNumber *)reactTag message:(NSString *)message)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNCWebView *> *viewRegistry) {
    RNCWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[RNCWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting RNCWebView, got: %@", view);
    } else {
      [view postMessage:message];
    }
  }];
}

RCT_CUSTOM_VIEW_PROPERTY(pullToRefreshEnabled, BOOL, RNCWebView) {
    view.pullToRefreshEnabled = json == nil ? false : [RCTConvert BOOL: json];
}

RCT_CUSTOM_VIEW_PROPERTY(bounces, BOOL, RNCWebView) {
  view.bounces = json == nil ? true : [RCTConvert BOOL: json];
}

RCT_CUSTOM_VIEW_PROPERTY(useSharedProcessPool, BOOL, RNCWebView) {
  view.useSharedProcessPool = json == nil ? true : [RCTConvert BOOL: json];
}

RCT_CUSTOM_VIEW_PROPERTY(scrollEnabled, BOOL, RNCWebView) {
  view.scrollEnabled = json == nil ? true : [RCTConvert BOOL: json];
}

RCT_CUSTOM_VIEW_PROPERTY(sharedCookiesEnabled, BOOL, RNCWebView) {
    view.sharedCookiesEnabled = json == nil ? false : [RCTConvert BOOL: json];
}

#if !TARGET_OS_OSX
RCT_CUSTOM_VIEW_PROPERTY(decelerationRate, CGFloat, RNCWebView) {
  view.decelerationRate = json == nil ? UIScrollViewDecelerationRateNormal : [RCTConvert CGFloat: json];
}
#endif // !TARGET_OS_OSX

RCT_CUSTOM_VIEW_PROPERTY(directionalLockEnabled, BOOL, RNCWebView) {
    view.directionalLockEnabled = json == nil ? true : [RCTConvert BOOL: json];
}

RCT_CUSTOM_VIEW_PROPERTY(showsHorizontalScrollIndicator, BOOL, RNCWebView) {
  view.showsHorizontalScrollIndicator = json == nil ? true : [RCTConvert BOOL: json];
}

RCT_CUSTOM_VIEW_PROPERTY(showsVerticalScrollIndicator, BOOL, RNCWebView) {
  view.showsVerticalScrollIndicator = json == nil ? true : [RCTConvert BOOL: json];
}

RCT_CUSTOM_VIEW_PROPERTY(keyboardDisplayRequiresUserAction, BOOL, RNCWebView) {
  view.keyboardDisplayRequiresUserAction = json == nil ? true : [RCTConvert BOOL: json];
}

RCT_EXPORT_METHOD(injectJavaScript:(nonnull NSNumber *)reactTag script:(NSString *)script)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNCWebView *> *viewRegistry) {
    RNCWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[RNCWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting RNCWebView, got: %@", view);
    } else {
      [view injectJavaScript:script];
    }
  }];
}

-(NSHTTPCookie *)makeHTTPCookieObject:(NSURL *)url
    props:(NSDictionary *)props
{
    NSString *topLevelDomain = url.host;

    if (isEmpty(topLevelDomain)){
        NSException* myException = [NSException
            exceptionWithName:@"Exception"
            reason:INVALID_URL_MISSING_HTTP
            userInfo:nil];
        @throw myException;
    }

    NSString *name = [RCTConvert NSString:props[@"name"]];
    NSString *value = [RCTConvert NSString:props[@"value"]];
    NSString *path = [RCTConvert NSString:props[@"path"]];
    NSString *domain = [RCTConvert NSString:props[@"domain"]];
    NSString *version = [RCTConvert NSString:props[@"version"]];
    NSDate *expires = [RCTConvert NSDate:props[@"expires"]];
    NSNumber *secure = [RCTConvert NSNumber:props[@"secure"]];
    NSNumber *httpOnly = [RCTConvert NSNumber:props[@"httpOnly"]];

    NSMutableDictionary *cookieProperties = [NSMutableDictionary dictionary];
    [cookieProperties setObject:name forKey:NSHTTPCookieName];
    [cookieProperties setObject:value forKey:NSHTTPCookieValue];

    if (!isEmpty(path)) {
        [cookieProperties setObject:path forKey:NSHTTPCookiePath];
    } else {
        [cookieProperties setObject:@"/" forKey:NSHTTPCookiePath];
    }
    if (!isEmpty(domain)) {
        // Stripping the leading . to ensure the following check is accurate
        NSString *strippedDomain = domain;
         if ([strippedDomain hasPrefix:@"."]) {
            strippedDomain = [strippedDomain substringFromIndex:1];
        }

        if (![topLevelDomain containsString:strippedDomain] &&
            ![topLevelDomain isEqualToString: strippedDomain]) {
                NSException* myException = [NSException
                    exceptionWithName:@"Exception"
                    reason: [NSString stringWithFormat:INVALID_DOMAINS, topLevelDomain, domain]
                    userInfo:nil];
                @throw myException;
        }

        [cookieProperties setObject:domain forKey:NSHTTPCookieDomain];
    } else {
        [cookieProperties setObject:topLevelDomain forKey:NSHTTPCookieDomain];
    }
    if (!isEmpty(version)) {
         [cookieProperties setObject:version forKey:NSHTTPCookieVersion];
    }
    if (!isEmpty(expires)) {
         [cookieProperties setObject:expires forKey:NSHTTPCookieExpires];
    }
    if (!isEmpty(secure)) {
        [cookieProperties setObject:secure forKey:@"secure"];
    }
    if (!isEmpty(httpOnly)) {
        [cookieProperties setObject:httpOnly forKey:@"HTTPOnly"];
    }

    NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:cookieProperties];

    return cookie;
}

RCT_EXPORT_METHOD(
    setCookie:(NSURL *)url
    cookie:(NSDictionary *)props
    useWebKit:(BOOL)useWebKit
    resolver:(RCTPromiseResolveBlock)resolve
    rejecter:(RCTPromiseRejectBlock)reject)
{
    NSHTTPCookie *cookie;
    @try {
        cookie = [self makeHTTPCookieObject:url props:props];
    }
    @catch ( NSException *e ) {
        reject(@"", [e reason], nil);
        return;
    }

    if (useWebKit) {
        if (@available(iOS 11.0, *)) {
            dispatch_async(dispatch_get_main_queue(), ^(){
                WKHTTPCookieStore *cookieStore = [[[RNCWKProcessPoolManager sharedManager] sharedDataStore] httpCookieStore];
                [cookieStore setCookie:cookie completionHandler:^() {
                    resolve(@(YES));
                }];
            });
        } else {
            reject(@"", NOT_AVAILABLE_ERROR_MESSAGE, nil);
        }
    } else {
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:cookie];
        resolve(@(YES));
    }
}

RCT_EXPORT_METHOD(
  resetDataStore
{
  dispatch_async(dispatch_get_main_queue(), ^(){
    [[RNCWKProcessPoolManager sharedManager] resetDataStore];
  });
}

RCT_EXPORT_METHOD(
    clearAllCookies:(BOOL)useWebKit
    resolver:(RCTPromiseResolveBlock)resolve
    rejecter:(RCTPromiseRejectBlock)reject)
{
    if (useWebKit) {
        if (@available(iOS 11.0, *)) {
            dispatch_async(dispatch_get_main_queue(), ^(){
                // https://stackoverflow.com/questions/46465070/how-to-delete-cookies-from-wkhttpcookiestore#answer-47928399
                NSSet *websiteDataTypes = [NSSet setWithArray:@[WKWebsiteDataTypeCookies]];
                NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
                [[[RNCWKProcessPoolManager sharedManager] sharedDataStore] removeDataOfTypes:websiteDataTypes
                                                        modifiedSince:dateFrom
                                                        completionHandler:^() {
                                                            resolve(@(YES));
                                                        }];
            });
        } else {
            reject(@"", NOT_AVAILABLE_ERROR_MESSAGE, nil);
        }
    } else {
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *c in cookieStorage.cookies) {
            [cookieStorage deleteCookie:c];
        }
        [[NSUserDefaults standardUserDefaults] synchronize];
        resolve(@(YES));
    }
}

RCT_EXPORT_METHOD(
    getAllCookies:(BOOL)useWebKit
    resolver:(RCTPromiseResolveBlock)resolve
    rejecter:(RCTPromiseRejectBlock)reject)
{
    if (useWebKit) {
        if (@available(iOS 11.0, *)) {
            dispatch_async(dispatch_get_main_queue(), ^(){
                WKHTTPCookieStore *cookieStore = [[[RNCWKProcessPoolManager sharedManager] sharedDataStore] httpCookieStore];
                [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *allCookies) {
                    resolve([self createCookieList: allCookies]);
                }];
            });
        } else {
            reject(@"", NOT_AVAILABLE_ERROR_MESSAGE, nil);
        }
    } else {
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        resolve([self createCookieList:cookieStorage.cookies]);
    }
}

-(NSDictionary *)createCookieList:(NSArray<NSHTTPCookie *>*)cookies
{
    NSMutableDictionary *cookieList = [NSMutableDictionary dictionary];
    for (NSHTTPCookie *cookie in cookies) {
        [cookieList setObject:[self createCookieData:cookie] forKey:cookie.name];
    }
    return cookieList;
}

-(NSDictionary *)createCookieData:(NSHTTPCookie *)cookie
{
    NSDateFormatter *formatter = [NSDateFormatter new];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"];
    
    NSMutableDictionary *cookieData = [NSMutableDictionary dictionary];
    [cookieData setObject:cookie.name forKey:@"name"];
    [cookieData setObject:cookie.value forKey:@"value"];
    [cookieData setObject:cookie.path forKey:@"path"];
    [cookieData setObject:cookie.domain forKey:@"domain"];
    [cookieData setObject:[NSString stringWithFormat:@"%@", @(cookie.version)] forKey:@"version"];
    if (!isEmpty(cookie.expiresDate)) {
        [cookieData setObject:[formatter stringFromDate:cookie.expiresDate] forKey:@"expires"];
    }
    [cookieData setObject:[NSNumber numberWithBool:(BOOL)cookie.secure] forKey:@"secure"];
    [cookieData setObject:[NSNumber numberWithBool:(BOOL)cookie.HTTPOnly] forKey:@"httpOnly"];
    return cookieData;
}

RCT_EXPORT_METHOD(goBack:(nonnull NSNumber *)reactTag)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNCWebView *> *viewRegistry) {
    RNCWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[RNCWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting RNCWebView, got: %@", view);
    } else {
      [view goBack];
    }
  }];
}

RCT_EXPORT_METHOD(goForward:(nonnull NSNumber *)reactTag)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNCWebView *> *viewRegistry) {
    RNCWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[RNCWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting RNCWebView, got: %@", view);
    } else {
      [view goForward];
    }
  }];
}

RCT_EXPORT_METHOD(reload:(nonnull NSNumber *)reactTag)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNCWebView *> *viewRegistry) {
    RNCWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[RNCWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting RNCWebView, got: %@", view);
    } else {
      [view reload];
    }
  }];
}

RCT_EXPORT_METHOD(stopLoading:(nonnull NSNumber *)reactTag)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNCWebView *> *viewRegistry) {
    RNCWebView *view = viewRegistry[reactTag];
    if (![view isKindOfClass:[RNCWebView class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting RNCWebView, got: %@", view);
    } else {
      [view stopLoading];
    }
  }];
}

#pragma mark - Exported synchronous methods

- (BOOL)          webView:(RNCWebView *)webView
shouldStartLoadForRequest:(NSMutableDictionary<NSString *, id> *)request
             withCallback:(RCTDirectEventBlock)callback
{
  _shouldStartLoadLock = [[NSConditionLock alloc] initWithCondition:arc4random()];
  _shouldStartLoad = YES;
  request[@"lockIdentifier"] = @(_shouldStartLoadLock.condition);
  callback(request);

  // Block the main thread for a maximum of 250ms until the JS thread returns
  if ([_shouldStartLoadLock lockWhenCondition:0 beforeDate:[NSDate dateWithTimeIntervalSinceNow:.25]]) {
    BOOL returnValue = _shouldStartLoad;
    [_shouldStartLoadLock unlock];
    _shouldStartLoadLock = nil;
    return returnValue;
  } else {
    RCTLogWarn(@"Did not receive response to shouldStartLoad in time, defaulting to YES");
    return YES;
  }
}

RCT_EXPORT_METHOD(startLoadWithResult:(BOOL)result lockIdentifier:(NSInteger)lockIdentifier)
{
  if ([_shouldStartLoadLock tryLockWhenCondition:lockIdentifier]) {
    _shouldStartLoad = result;
    [_shouldStartLoadLock unlockWithCondition:0];
  } else {
    RCTLogWarn(@"startLoadWithResult invoked with invalid lockIdentifier: "
               "got %lld, expected %lld", (long long)lockIdentifier, (long long)_shouldStartLoadLock.condition);
  }
}

@end
