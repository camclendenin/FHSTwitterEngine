//
//  FHSOAuthLoginController.m
//  FHSTwitterEngine
//
//  Created by Nathaniel Symer on 3/10/14.
//  Copyright (c) 2014 Nathaniel Symer. All rights reserved.
//

#import "FHSTwitterEngineController.h"
#import "NSString+FHSTE.h"
#import "FHSTwitterEngine.h"

static NSString * const newPinJS = @"var d = document.getElementById('oauth-pin'); if (d == null) d = document.getElementById('oauth_pin'); if (d) { var d2 = d.getElementsByTagName('code'); if (d2.length > 0) d2[0].innerHTML; }";
static NSString * const oldPinJS = @"var d = document.getElementById('oauth-pin'); if (d == null) d = document.getElementById('oauth_pin'); if (d) d = d.innerHTML; d;";

@implementation FHSTwitterEngineController

+ (FHSTwitterEngineController *)controllerWithCompletionBlock:(LoginControllerBlock)block {
    return [[[self class]alloc]initWithCompletionBlock:block];
}

- (instancetype)initWithCompletionBlock:(LoginControllerBlock)block {
    self = [super init];
    if (self) {
        self.block = block;
    }
    return self;
}

- (void)loadView {
    [super loadView];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(pasteboardChanged:) name:UIPasteboardChangedNotification object:nil];
    
    self.view = [[UIView alloc]initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = [UIColor lightGrayColor];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    self.navBar = [[UINavigationBar alloc]initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, (UIDevice.currentDevice.systemVersion.floatValue >= 7.0f)?64:44)];
    _navBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    UINavigationItem *navItem = [[UINavigationItem alloc]initWithTitle:@"Twitter Login"];
	navItem.leftBarButtonItem = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)];
	[_navBar pushNavigationItem:navItem animated:NO];
    
    self.theWebView = [[UIWebView alloc]initWithFrame:CGRectMake(0, _navBar.bounds.size.height, self.view.bounds.size.width, self.view.bounds.size.height-_navBar.bounds.size.height)];
    _theWebView.hidden = YES;
    _theWebView.delegate = self;
    _theWebView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _theWebView.dataDetectorTypes = UIDataDetectorTypeNone;
    _theWebView.scrollView.clipsToBounds = NO;
    _theWebView.backgroundColor = [UIColor lightGrayColor];
    [self.view addSubview:_theWebView];
    [self.view addSubview:_navBar];
    
    self.loadingText = [[UILabel alloc]initWithFrame:CGRectMake((self.view.bounds.size.width/2)-40, (self.view.bounds.size.height/2)-10-7.5, 100, 15)];
	_loadingText.text = @"Please Wait...";
	_loadingText.backgroundColor = [UIColor clearColor];
	_loadingText.textColor = [UIColor blackColor];
	_loadingText.textAlignment = NSTextAlignmentLeft;
	_loadingText.font = [UIFont boldSystemFontOfSize:15];
	[self.view addSubview:_loadingText];
	
	self.spinner = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	_spinner.center = CGPointMake((self.view.bounds.size.width/2)-60, (self.view.bounds.size.height/2)-10);
	[self.view addSubview:_spinner];
	[_spinner startAnimating];
    
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            id res = [[FHSTwitterEngine sharedEngine]getRequestToken];

            if ([res isKindOfClass:[NSString class]]) {
                self.requestToken = [FHSToken tokenWithHTTPResponseBody:(NSString *)res];
                NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.twitter.com/oauth/authorize?oauth_token=%@",_requestToken.key]]];
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    @autoreleasepool {
                        [_theWebView loadRequest:request];
                    }
                });
            } else {
                double delayInSeconds = 0.5;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_main_queue(),^(void) {
                    @autoreleasepool {
                        [self dismissViewControllerAnimated:YES completion:^(void){
                            if (_block) {
                                _block(FHSTwitterEngineControllerResultFailed);
                            }
                        }];
                    }
                });
            }
        }
    });
}

- (void)gotPin:(NSString *)pin {
    _requestToken.verifier = pin;
    BOOL ret = [[FHSTwitterEngine sharedEngine]finishAuthWithRequestToken:_requestToken];
    
    if (_block) {
        _block(ret?FHSTwitterEngineControllerResultSucceeded:FHSTwitterEngineControllerResultFailed);
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)pasteboardChanged:(NSNotification *)note {
	if (![note.userInfo objectForKey:UIPasteboardChangedTypesAddedKey]) {
        return;
    }
    
    NSString *string = [[UIPasteboard generalPasteboard]string];
	
	if (string.length != 7 || !string.fhs_isNumeric) {
        return;
    }
	
	[self gotPin:string];
}

- (NSString *)locatePin {
	NSString *pin = [[_theWebView stringByEvaluatingJavaScriptFromString:newPinJS]stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	if (pin.length == 7 && pin.fhs_isNumeric) {
		return pin;
	} else {
		pin = [[_theWebView stringByEvaluatingJavaScriptFromString:oldPinJS]stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		if (pin.length == 7 && pin.fhs_isNumeric) {
			return pin;
		}
	}
	return nil;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    _theWebView.userInteractionEnabled = YES;
    NSString *authPin = [self locatePin];
    
    if (authPin.length > 0) {
        [self gotPin:authPin];
        return;
    }
    
    NSString *formCount = [webView stringByEvaluatingJavaScriptFromString:@"document.forms.length"];
    
    if ([formCount isEqualToString:@"0"]) {
        _navBar.topItem.title = @"Select and Copy the PIN";
    }
	
	[UIView beginAnimations:nil context:nil];
    _spinner.hidden = YES;
    _loadingText.hidden = YES;
	[UIView commitAnimations];
	
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    
    _theWebView.hidden = NO;
}

- (void)webViewDidStartLoad:(UIWebView *)webView {
    _theWebView.userInteractionEnabled = NO;
    [_theWebView setHidden:YES];
    _spinner.hidden = NO;
    _loadingText.hidden = NO;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    if (strstr([request.URL.absoluteString UTF8String], "denied=")) {
		[self dismissViewControllerAnimated:YES completion:nil];
        return NO;
    }
    
    NSData *data = request.HTTPBody;
	char *raw = data?(char *)[data bytes]:"";
	
	if (raw && (strstr(raw, "cancel=") || strstr(raw, "deny="))) {
        [self close];
		return NO;
	}
    
	return YES;
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:^(void){
        if (_block) {
            _block(FHSTwitterEngineControllerResultCancelled);
        }
    }];
}

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    [_theWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@""]]];
    [super dismissViewControllerAnimated:flag completion:completion];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter]removeObserver:self];
}

@end