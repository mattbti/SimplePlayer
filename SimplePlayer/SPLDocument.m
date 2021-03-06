//
//  SPLDocument.m
//  SimplePlayer
//
//  Created by Matthew Doig on 2/26/14.
//  Copyright (c) 2014 BTI. All rights reserved.
//

#import "SPLDocument.h"
#import "SPLOverlayLayer.h"
#import "GLEssentialsGLView.h"
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>

static void *AVSPPlayerItemStatusContext = &AVSPPlayerItemStatusContext;
static void *AVSPPlayerRateContext = &AVSPPlayerRateContext;
static void *AVSPPlayerLayerReadyForDisplay = &AVSPPlayerLayerReadyForDisplay;

@interface SPLDocument ()

@property (nonatomic, strong) AVMutableComposition *composition;

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) NSView *playerView;

@property (nonatomic, strong) GLEssentialsGLView *glView;
@property (nonatomic, strong) WebView *mapView;

@property (nonatomic, strong) SPLOverlayLayer *overlayLayer;
@property (nonatomic, strong) NSView *overlayView;

@property (nonatomic, strong) id timeObserverToken;

@property (nonatomic, assign) NSRect playerFrame;
@property (nonatomic, assign) double playerScaleHeight;
@property (nonatomic, assign) double playerScaleWidth;

@end

@implementation SPLDocument

- (id)init
{
    self = [super init];
    if (self) {
        // Add your subclass-specific initialization here.
    }
    return self;
}

- (NSString *)windowNibName
{
    return @"SPLDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)windowController
{
    [super windowControllerDidLoadNib:windowController];
	[[windowController window] setMovableByWindowBackground:YES];
    [[[self containerView] layer] setBackgroundColor:CGColorGetConstantColor(kCGColorBlack)];
    [self setUpBg];
	[[self loadingSpinner] startAnimation:self];
	
	// Create the AVPlayer, add rate and status observers
	self.player = [[AVPlayer alloc] init];
	[self addObserver:self forKeyPath:@"player.rate" options:NSKeyValueObservingOptionNew context:AVSPPlayerRateContext];
	[self addObserver:self forKeyPath:@"player.currentItem.status" options:NSKeyValueObservingOptionNew context:AVSPPlayerItemStatusContext];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoPlayerDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
	
	// Create an asset with our URL, asychronously load its tracks, its duration, and whether it's playable or protected.
	// When that loading is complete, configure a player to play the asset.
	AVURLAsset *asset = [AVAsset assetWithURL:[self fileURL]];
	NSArray *assetKeysToLoadAndTest = [NSArray arrayWithObjects:@"playable", @"hasProtectedContent", @"tracks", @"duration", nil];
	[asset loadValuesAsynchronouslyForKeys:assetKeysToLoadAndTest completionHandler:^(void) {
		
		// The asset invokes its completion handler on an arbitrary queue when loading is complete.
		// Because we want to access our AVPlayer in our ensuing set-up, we must dispatch our handler to the main queue.
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			
			[self setUpPlaybackOfAsset:asset withKeys:assetKeysToLoadAndTest];
			[self setUpMap];
		});
		
	}];
}

- (void)videoPlayerDidReachEnd:(NSNotification *)notification
{
    [self.player.currentItem seekToTime:kCMTimeZero];
}

- (void)setUpPlaybackOfAsset:(AVAsset *)asset withKeys:(NSArray *)keys
{
	// This method is called when the AVAsset for our URL has completing the loading of the values of the specified array of keys.
	// We set up playback of the asset here.
	
	// First test whether the values of each of the keys we need have been successfully loaded.
	for (NSString *key in keys)
	{
		NSError *error = nil;
		
		if ([asset statusOfValueForKey:key error:&error] == AVKeyValueStatusFailed)
		{
			[self stopLoadingAnimationAndHandleError:error];
			return;
		}
	}
	
	if (![asset isPlayable] || [asset hasProtectedContent])
	{
		// We can't play this asset. Show the "Unplayable Asset" label.
		[self stopLoadingAnimationAndHandleError:nil];
		[[self unplayableLabel] setHidden:NO];
		return;
	}
	
	if ([[asset tracksWithMediaType:AVMediaTypeVideo] count] != 0)
	{
		AVPlayerLayer *newPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:[self player]];
        newPlayerLayer.frame = self.playerView.layer.bounds;
        newPlayerLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        newPlayerLayer.hidden = YES;
        [self.playerView.layer addSublayer:newPlayerLayer];
        self.PlayerLayer = newPlayerLayer;
        [self addObserver:self forKeyPath:@"playerLayer.readyForDisplay" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:AVSPPlayerLayerReadyForDisplay];
    }
	else
	{
		// This asset has no video tracks. Show the "No Video" label.
		[self stopLoadingAnimationAndHandleError:nil];
		[[self noVideoLabel] setHidden:NO];
	}
	
	// Create a new AVPlayerItem and make it our player's current item.
    AVMutableComposition *composition = [[AVMutableComposition alloc] init];
    CMTimeRange editRange = CMTimeRangeMake(CMTimeMake(0, 600), CMTimeMake(asset.duration.value, asset.duration.timescale));
    NSError *editError;
    BOOL result = [composition insertTimeRange:editRange ofAsset:asset atTime:composition.duration error:&editError];
    int numOfCopies = 100;
    if (result) {
        for (int i = 0; i < numOfCopies; i++) {
            [composition insertTimeRange:editRange ofAsset:asset atTime:composition.duration error:&editError];
        }
    }
    
	AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:composition];
	[[self player] replaceCurrentItemWithPlayerItem:playerItem];
	
    [self setTimeObserverToken:[[self player] addPeriodicTimeObserverForInterval:CMTimeMake(1, 10) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            [[self timeSlider] setDoubleValue:CMTimeGetSeconds(time)];
	}]];
}

- (void)setUpBg
{
    self.playerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.containerView.frame.size.width, self.containerView.frame.size.height)];
    [self.playerView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self.containerView addSubview:self.playerView positioned:NSWindowAbove relativeTo:self.containerView];
}

- (void)setUpOverlay
{
    NSRect frame = NSMakeRect(self.containerView.frame.origin.x + self.playerFrame.origin.x , self.containerView.frame.origin.y + self.playerFrame.origin.y, self.playerFrame.size.width, self.playerFrame.size.height);
    self.overlayView = [[NSView alloc] initWithFrame:frame];
    self.overlayLayer = [[SPLOverlayLayer alloc] initWithBounds:frame];
    self.overlayView.layer = self.overlayLayer;
    [self.containerView addSubview:self.overlayView positioned:NSWindowAbove relativeTo:self.mapView];
}

- (void)calculateScale
{
    float aspectRatio = self.playerView.frame.size.width / self.playerView.frame.size.height;
    float x = 0;
    float y = 0;
    float width = self.playerView.frame.size.width;
    float height = self.playerView.frame.size.height;
    if (aspectRatio < (16.0f/9.0f)) {
        height = (self.playerView.frame.size.width / 16.0f) * 9.0f;
        y = (self.playerView.frame.size.height - height) / 2.0f;
    };
    if (aspectRatio > (16.0f/9.0f)) {
        width = (self.playerView.frame.size.height / 9.0f) * 16.0f;
        x = (self.playerView.frame.size.width - width) / 2.0f;
    };
    self.playerFrame = NSMakeRect(x, y, width, height);
    self.playerScaleWidth =  self.playerFrame.size.width / 16.0f;
    self.playerScaleHeight =  self.playerFrame.size.height / 9.0f ;
}

- (NSRect)createMapFrame
{
    [self calculateScale];
    NSRect frame;
    frame.origin.x = self.playerFrame.origin.x + (2.57f * self.playerScaleWidth);
    frame.origin.y = self.playerFrame.origin.y + (.33f * self.playerScaleHeight);
    frame.size.width = 11.02 * self.playerScaleWidth;
    frame.size.height = 6.19 * self.playerScaleHeight;
    return frame;
}

- (NSRect)createMapFrameFull
{
    [self calculateScale];
    NSRect frame;
    frame.origin.x = self.playerFrame.origin.x;
    frame.origin.y = self.playerFrame.origin.y;
    frame.size.width = 16 * self.playerScaleWidth;
    frame.size.height = 9 * self.playerScaleHeight;
    return frame;
}

- (void)setUpMap
{
    NSRect frame = [self createMapFrame];
    
    self.mapView = [[WebView alloc] initWithFrame:frame];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"GoogleEarth" ofType:@"html"];
    NSURL *baseURL = [NSURL fileURLWithPath:path];
    NSURL *fullURL = [NSURL URLWithString:@"#geplugin_browserok" relativeToURL:baseURL];
    NSURLRequest *request = [NSURLRequest requestWithURL:fullURL];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mapViewFinishedLoading:)
                                                 name:WebViewProgressFinishedNotification
                                               object:self.mapView];
    [[self.mapView mainFrame] loadRequest:request];
    
    self.glView = [[GLEssentialsGLView alloc] initWithFrame:frame];
    
    
    [self.glView setHidden:YES];
    [self.containerView addSubview:self.glView positioned:NSWindowAbove relativeTo:self.playerView];
    
    [self.mapView setHidden:YES];
    [self.containerView addSubview:self.mapView positioned:NSWindowAbove relativeTo:self.glView];
}

- (void)mapViewFinishedLoading:(NSNotification *)notification {
    // set window.external as soon as the web view is done loading
    // the page
    
    // http://developer.apple.com/DOCUMENTATION/AppleApplications/Conceptual/SafariJSProgTopics/Tasks/ObjCFromJavaScript.html
    [[self.mapView windowScriptObject] setValue:self forKey:@"external"];
    [self createPlacemark];
}

- (void)createPlacemark {
    // call a JS function, passing in the text field's value
    
    // http://developer.apple.com/DOCUMENTATION/Cocoa/Conceptual/DisplayWebContent/Tasks/JavaScriptFromObjC.html
    [[self.mapView windowScriptObject] callWebScriptMethod:@"JSCreatePlacemarkAtCameraCenter"
                                        withArguments:[NSArray arrayWithObjects:@"Nashville, TN", nil]];
}

- (void)stopLoadingAnimationAndHandleError:(NSError *)error
{
	[[self loadingSpinner] stopAnimation:self];
	[[self loadingSpinner] setHidden:YES];
	if (error)
	{
		[self presentError:error
			modalForWindow:[self windowForSheet]
				  delegate:nil
		didPresentSelector:NULL
			   contextInfo:nil];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == AVSPPlayerItemStatusContext)
	{
		AVPlayerStatus status = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
		BOOL enable = NO;
		switch (status)
		{
			case AVPlayerItemStatusUnknown:
				break;
			case AVPlayerItemStatusReadyToPlay:
				enable = YES;
				break;
			case AVPlayerItemStatusFailed:
				[self stopLoadingAnimationAndHandleError:[[[self player] currentItem] error]];
				break;
		}
		
		[[self playPauseButton] setEnabled:enable];
		[[self fastForwardButton] setEnabled:enable];
		[[self rewindButton] setEnabled:enable];
	}
	else if (context == AVSPPlayerRateContext)
	{
		float rate = [[change objectForKey:NSKeyValueChangeNewKey] floatValue];
		if (rate != 1.f)
		{
			[[self playPauseButton] setTitle:@"Play"];
		}
		else
		{
			[[self playPauseButton] setTitle:@"Pause"];
		}
	}
	else if (context == AVSPPlayerLayerReadyForDisplay)
	{
		if ([[change objectForKey:NSKeyValueChangeNewKey] boolValue] == YES)
		{
			// The AVPlayerLayer is ready for display. Hide the loading spinner and show it.
			[self stopLoadingAnimationAndHandleError:nil];
			[[self playerLayer] setHidden:NO];
        }
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)close
{
	[[self player] pause];
	[[self player] removeTimeObserver:[self timeObserverToken]];
	[self setTimeObserverToken:nil];
	[self removeObserver:self forKeyPath:@"player.rate"];
	[self removeObserver:self forKeyPath:@"player.currentItem.status"];
	if ([self playerLayer])
		[self removeObserver:self forKeyPath:@"playerLayer.readyForDisplay"];
	[super close];
}

+ (NSSet *)keyPathsForValuesAffectingDuration
{
	return [NSSet setWithObjects:@"player.currentItem", @"player.currentItem.status", nil];
}

- (double)duration
{
	AVPlayerItem *playerItem = [[self player] currentItem];
	
	if ([playerItem status] == AVPlayerItemStatusReadyToPlay)
		return CMTimeGetSeconds([[playerItem asset] duration]);
	else
		return 0.f;
}

- (double)currentTime
{
	return CMTimeGetSeconds([[self player] currentTime]);
}

- (void)setCurrentTime:(double)time
{
	[[self player] seekToTime:CMTimeMakeWithSeconds(time, 1) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

/*
+ (NSSet *)keyPathsForValuesAffectingVolume
{
	return [NSSet setWithObject:@"glView.opacity"];
}
*/

- (float)volume
{
	return [[self glView] opacity];
}

- (void)setVolume:(float)volume
{
	[[self glView] setOpacity:volume];
}

- (IBAction)playPauseToggle:(id)sender
{
    if ([[self player] rate] != 1.f)
	{
		if ([self currentTime] == [self duration])
			[self setCurrentTime:0.f];
		[[self player] play];
        NSRect frame = [self createMapFrame];
        [self.mapView setFrame:frame];
        [self.glView setFrame:frame];
        [self setUpOverlay];
	}
	else
	{
		[[self player] pause];
	}
}

- (IBAction)showDistrict1:(id)sender
{
    [self.mapView setHidden:NO];
    [self.glView setHidden:YES];
    
    [[self.mapView windowScriptObject] callWebScriptMethod:@"JSDistrict1"
                                             withArguments:@[]];
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [self.overlayLayer updateComplete];
    }];
    CATransition *transition = [CATransition animation];
    transition.duration = 1.5;
    transition.type = kCATransitionFade;
    [self.overlayView.layer addAnimation:transition forKey:nil];
    
    self.overlayLayer.raceName = @"TN HOUSE DISTRICT 1";
    self.overlayLayer.candidateName1 = @"WOODRUFF";
    self.overlayLayer.candidateHeadshot1 = [[NSBundle mainBundle] pathForResource:@"AndyHarris" ofType:@"png"];
    self.overlayLayer.candidateVotes1 =@"47,597";
    self.overlayLayer.candidatePercent1 = @"19.9%";
    self.overlayLayer.candidateWin1 = NO;
    self.overlayLayer.candidateName2 = @"ROE";
    self.overlayLayer.candidateHeadshot2 = [[NSBundle mainBundle] pathForResource:@"PeterKing" ofType:@"png"];
    self.overlayLayer.candidateVotes2 =@"182,186";
    self.overlayLayer.candidatePercent2 = @"76.1%";
    self.overlayLayer.candidateWin2 = YES;
    [self.overlayLayer update];
    [CATransaction commit];
}

- (IBAction)showDistrict5:(id)sender
{
    [self.mapView setHidden:NO];
    [self.glView setHidden:YES];
    
    [[self.mapView windowScriptObject] callWebScriptMethod:@"JSDistrict5"
                                             withArguments:@[]];
    
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [self.overlayLayer updateComplete];
    }];
    CATransition *transition = [CATransition animation];
    transition.duration = 1.5;
    transition.type = kCATransitionFade;
    [self.overlayView.layer addAnimation:transition forKey:nil];
    
    self.overlayLayer.raceName = @"Tennessee House District 5";
    self.overlayLayer.candidateName1 = @"COOPER";
    self.overlayLayer.candidateHeadshot1 = [[NSBundle mainBundle] pathForResource:@"JimDeMint" ofType:@"png"];
    self.overlayLayer.candidateVotes1 =@"166,999";
    self.overlayLayer.candidatePercent1 = @"65.2%";
    self.overlayLayer.candidateWin1 = YES;
    self.overlayLayer.candidateName2 = @"STAATS";
    self.overlayLayer.candidateHeadshot2 = [[NSBundle mainBundle] pathForResource:@"BradEllsworth" ofType:@"png"];
    self.overlayLayer.candidateVotes2 =@"83,982";
    self.overlayLayer.candidatePercent2 = @"32.8%";
    self.overlayLayer.candidateWin2 = NO;
    [self.overlayLayer update];
    [CATransaction commit];
}

- (IBAction)showPresident:(id)sender
{
    [self.mapView setHidden:NO];
    [self.glView setHidden:YES];
    
    [[self.mapView windowScriptObject] callWebScriptMethod:@"JSPresident"
                                             withArguments:@[]];
    
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [self.overlayLayer updateComplete];
    }];
    CATransition *transition = [CATransition animation];
    transition.duration = 1.5;
    transition.type = kCATransitionFade;
    [self.overlayView.layer addAnimation:transition forKey:nil];
    
    self.overlayLayer.raceName = @"Tennessee President";
    self.overlayLayer.candidateName1 = @"OBAMA";
    self.overlayLayer.candidateHeadshot1 = [[NSBundle mainBundle] pathForResource:@"Obama" ofType:@"png"];
    self.overlayLayer.candidateVotes1 =@"679,340";
    self.overlayLayer.candidatePercent1 = @"37.8%";
    self.overlayLayer.candidateWin1 = NO;
    self.overlayLayer.candidateName2 = @"ROMNEY";
    self.overlayLayer.candidateHeadshot2 = [[NSBundle mainBundle] pathForResource:@"Romney" ofType:@"png"];
    self.overlayLayer.candidateVotes2 =@"1,087,127";
    self.overlayLayer.candidatePercent2 = @"60.5%";
    self.overlayLayer.candidateWin2 = YES;
    [self.overlayLayer update];
    [CATransaction commit];
}

- (IBAction)showPres3D:(id)sender
{
    [self.mapView setHidden:YES];
    
    [self.glView setHidden:NO];
    [self.glView initTN];
    
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [self.overlayLayer updateComplete];
    }];
    CATransition *transition = [CATransition animation];
    transition.duration = 1.5;
    transition.type = kCATransitionFade;
    [self.overlayView.layer addAnimation:transition forKey:nil];
    
    self.overlayLayer.raceName = @"Tennessee President";
    self.overlayLayer.candidateName1 = @"OBAMA";
    self.overlayLayer.candidateHeadshot1 = [[NSBundle mainBundle] pathForResource:@"Obama" ofType:@"png"];
    self.overlayLayer.candidateVotes1 =@"679,340";
    self.overlayLayer.candidatePercent1 = @"37.8%";
    self.overlayLayer.candidateWin1 = NO;
    self.overlayLayer.candidateName2 = @"ROMNEY";
    self.overlayLayer.candidateHeadshot2 = [[NSBundle mainBundle] pathForResource:@"Romney" ofType:@"png"];
    self.overlayLayer.candidateVotes2 =@"1,087,127";
    self.overlayLayer.candidatePercent2 = @"60.5%";
    self.overlayLayer.candidateWin2 = YES;
    [self.overlayLayer update];
    [CATransaction commit];
}
- (IBAction)showPRCA:(id)sender
{
    [self.mapView setHidden:YES];
    [self.glView setHidden:NO];
    
    [self.glView initCA];
    
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [self.overlayLayer updateComplete];
    }];
    CATransition *transition = [CATransition animation];
    transition.duration = 1.5;
    transition.type = kCATransitionFade;
    [self.overlayView.layer addAnimation:transition forKey:nil];
    
    self.overlayLayer.raceName = @"California President";
    self.overlayLayer.candidateName1 = @"OBAMA";
    self.overlayLayer.candidateHeadshot1 = [[NSBundle mainBundle] pathForResource:@"Obama" ofType:@"png"];
    self.overlayLayer.candidateVotes1 =@"7,854,285";
    self.overlayLayer.candidatePercent1 = @"60.24%";
    self.overlayLayer.candidateWin1 = YES;
    self.overlayLayer.candidateName2 = @"ROMNEY";
    self.overlayLayer.candidateHeadshot2 = [[NSBundle mainBundle] pathForResource:@"Romney" ofType:@"png"];
    self.overlayLayer.candidateVotes2 =@"4,839,958";
    self.overlayLayer.candidatePercent2 = @"37.12%";
    self.overlayLayer.candidateWin2 = NO;
    [self.overlayLayer update];
    [CATransaction commit];
}

- (IBAction)showPresCnty:(id)sender
{
    [self.mapView setHidden:YES];
    
    [self.glView setHidden:NO];
    [self.glView initTNCnty];
    
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [self.overlayLayer updateComplete];
    }];
    CATransition *transition = [CATransition animation];
    transition.duration = 1.5;
    transition.type = kCATransitionFade;
    [self.overlayView.layer addAnimation:transition forKey:nil];
    
    self.overlayLayer.raceName = @"Tennessee President";
    self.overlayLayer.candidateName1 = @"OBAMA";
    self.overlayLayer.candidateHeadshot1 = [[NSBundle mainBundle] pathForResource:@"Obama" ofType:@"png"];
    self.overlayLayer.candidateVotes1 =@"679,340";
    self.overlayLayer.candidatePercent1 = @"37.8%";
    self.overlayLayer.candidateWin1 = NO;
    self.overlayLayer.candidateName2 = @"ROMNEY";
    self.overlayLayer.candidateHeadshot2 = [[NSBundle mainBundle] pathForResource:@"Romney" ofType:@"png"];
    self.overlayLayer.candidateVotes2 =@"1,087,127";
    self.overlayLayer.candidatePercent2 = @"60.5%";
    self.overlayLayer.candidateWin2 = YES;
    [self.overlayLayer update];
    [CATransaction commit];
}

- (IBAction)showPresUSA:(id)sender
{
    [self.mapView setHidden:YES];
    [self.glView setHidden:NO];
    
    [self.glView initUSA];
    
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [self.overlayLayer updateComplete];
    }];
    CATransition *transition = [CATransition animation];
    transition.duration = 1.5;
    transition.type = kCATransitionFade;
    [self.overlayView.layer addAnimation:transition forKey:nil];
    
    self.overlayLayer.raceName = @"President";
    self.overlayLayer.candidateName1 = @"OBAMA";
    self.overlayLayer.candidateHeadshot1 = [[NSBundle mainBundle] pathForResource:@"Obama" ofType:@"png"];
    self.overlayLayer.candidateVotes1 =@"332";
    self.overlayLayer.candidatePercent1 = @"61.71%";
    self.overlayLayer.candidateWin1 = YES;
    self.overlayLayer.candidateName2 = @"ROMNEY";
    self.overlayLayer.candidateHeadshot2 = [[NSBundle mainBundle] pathForResource:@"Romney" ofType:@"png"];
    self.overlayLayer.candidateVotes2 =@"206";
    self.overlayLayer.candidatePercent2 = @"39.29%";
    self.overlayLayer.candidateWin2 = NO;
    [self.overlayLayer update];
    [CATransaction commit];
}

- (IBAction)showPresWA:(id)sender
{
    [self.mapView setHidden:YES];
    [self.glView setHidden:NO];
    
    [self.glView initWA];
    
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [self.overlayLayer updateComplete];
    }];
    CATransition *transition = [CATransition animation];
    transition.duration = 1.5;
    transition.type = kCATransitionFade;
    [self.overlayView.layer addAnimation:transition forKey:nil];
    
    self.overlayLayer.raceName = @"Washington President";
    self.overlayLayer.candidateName1 = @"OBAMA";
    self.overlayLayer.candidateHeadshot1 = [[NSBundle mainBundle] pathForResource:@"Obama" ofType:@"png"];
    self.overlayLayer.candidateVotes1 =@"1,755,396";
    self.overlayLayer.candidatePercent1 = @"56.2%";
    self.overlayLayer.candidateWin1 = YES;
    self.overlayLayer.candidateName2 = @"ROMNEY";
    self.overlayLayer.candidateHeadshot2 = [[NSBundle mainBundle] pathForResource:@"Romney" ofType:@"png"];
    self.overlayLayer.candidateVotes2 =@"1,290,670";
    self.overlayLayer.candidatePercent2 = @"41.3%";
    self.overlayLayer.candidateWin2 = NO;
    [self.overlayLayer update];
    [CATransaction commit];
}

- (IBAction)showMapFULL:(id)sender
{
    NSRect frame = [self createMapFrameFull];
    [self.mapView setFrame:frame];
    [self.glView setFrame:frame];
}

- (IBAction)showMapWin:(id)sender
{
    NSRect frame = [self createMapFrame];
    [self.mapView setFrame:frame];
    [self.glView setFrame:frame];
}

- (IBAction)showBg:(id)sender
{
    [self.playerView.layer setHidden:NO];
    
    [self.glView.layer setHidden:YES];
    
    [self.overlayView.layer setHidden:YES];
}

- (IBAction)showMap:(id)sender
{
    [self.playerView.layer setHidden:YES];
    
    [self.glView.layer setHidden:NO];
    
    [self.overlayView.layer setHidden:YES];
}

- (IBAction)showOver:(id)sender
{
    [self.playerView.layer setHidden:YES];
    
    [self.glView.layer setHidden:YES];
    
    [self.overlayView.layer setHidden:NO];
}

- (IBAction)showAll:(id)sender
{
    [self.playerView.layer setHidden:NO];
    
    [self.glView.layer setHidden:NO];
    
    [self.overlayView.layer setHidden:NO];
}

+ (BOOL)autosavesInPlace
{
    return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    if (outError != NULL)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];
	return nil;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
    if (outError != NULL)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:NULL];
	return YES;
}

@end
