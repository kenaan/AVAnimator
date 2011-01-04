//
//  AVAnimatorView.h
//
//  Created by Moses DeJong on 3/18/09.
//

#import <UIKit/UIKit.h>

#define AVAnimator30FPS (1.0/30)
#define AVAnimator24FPS (1.0/24)
#define AVAnimator15FPS (1.0/15)
#define AVAnimator10FPS (1.0/10)
#define AVAnimator5FPS (1.0/5)

// AVAnimatorPreparedToAnimateNotification is delivered after resources
// have been loaded and the view is ready to animate.

// AVAnimatorDidStartNotification is delivered when an animation starts (once for each loop)
// AVAnimatorDidStopNotification is delivered when an animation stops (once for each loop)

// AVAnimatorDidPauseNotification is deliverd when the animation is paused, for example
// if a call comes in to the iPhone or when the pause button in movie controls is pressed.

// AVAnimatorDidUnpauseNotification is devliered when a pause is undone, so playing agan

// AVAnimatorDoneNotification is invoked when done animating, if a number of loops were
// requested then the done notification is delivered once all the loops have been played.

#define AVAnimatorPreparedToAnimateNotification @"AVAnimatorPreparedToAnimateNotification"
#define AVAnimatorDidStartNotification @"AVAnimatorDidStartNotification"
#define AVAnimatorDidStopNotification @"AVAnimatorDidStopNotification"
#define AVAnimatorDidPauseNotification @"AVAnimatorDidPauseNotification"
#define AVAnimatorDidUnpauseNotification @"AVAnimatorDidUnpauseNotification"
#define AVAnimatorDoneNotification @"AVAnimatorDoneNotification"

@class AVAudioPlayer;
@class NSURL;
@class CGFrameBuffer;
@class AVFrameDecoder;
@class AVResourceLoader;

typedef enum AVAnimatorPlayerState {
	ALLOCATED = 0,
	LOADED = 1,
	PREPPING = 2,
	READY = 3,
	ANIMATING = 4,
	STOPPED = 5,
	PAUSED = 6
} AVAudioPlayerState;

@interface AVAnimatorView : UIImageView {
@public
  
	AVResourceLoader *m_resourceLoader;
	AVFrameDecoder *m_frameDecoder;
  
	NSTimeInterval m_animationFrameDuration;
	NSUInteger m_animationNumFrames;
	NSInteger m_animationRepeatCount;
	UIImageOrientation m_animationOrientation;
  
@private
  
	NSURL *m_animationAudioURL;	
	UIImage *m_prevFrame;
	UIImage *m_nextFrame;
  
	NSArray *m_cgFrameBuffers;
  
	NSTimer *m_animationPrepTimer;
	NSTimer *m_animationReadyTimer;
	NSTimer *m_animationDecodeTimer;
	NSTimer *m_animationDisplayTimer;
	
	NSUInteger m_currentFrame;
  
	NSUInteger m_repeatedFrameCount;
  
	AVAudioPlayer *m_avAudioPlayer;
	id m_originalAudioDelegate;
	id m_retainedAudioDelegate;
  NSDate *m_audioSimulatedStartTime;
  
	AVAudioPlayerState m_state;
  
	NSTimeInterval m_animationMaxClockTime;
	NSTimeInterval m_animationDecodeTimerInterval;
  
	CGSize m_renderSize;
  
	// Becomes TRUE the first time the state changes to READY
	// and stays TRUE after that. This flag is needed to handle
	// the case where the player is stopped before it becomes
	// ready to animate. A change from STOPPED to ANIMATING
	// is only valid if the state has been READY already.
  
	BOOL m_isReadyToAnimate;
  
	// Set to TRUE if startAnimating is called before the
	// prepare phase is complete.
  
	BOOL m_startAnimatingWhenReady;
}

// public properties

@property (nonatomic, retain) AVResourceLoader *resourceLoader;
@property (nonatomic, retain) AVFrameDecoder *frameDecoder;

@property (nonatomic, assign) NSTimeInterval animationFrameDuration;
@property (nonatomic, assign) NSUInteger animationNumFrames;
@property (nonatomic, assign) NSInteger animationRepeatCount;
@property (nonatomic, assign) UIImageOrientation animationOrientation;

// static ctor : create view that has the screen dimensions
+ (AVAnimatorView*) aVAnimatorView;
// static ctor : create view with the given dimensions
+ (AVAnimatorView*) aVAnimatorViewWithFrame:(CGRect)viewFrame;

- (void) startAnimating;
- (void) stopAnimating;
- (BOOL) isAnimating;
- (BOOL) isInitializing;
- (void) doneAnimating;

- (void) pause;
- (void) unpause;
- (void) rewind;

- (void) animationShowFrame: (NSInteger) frame;

- (void) rotateToPortrait;

- (void) rotateToLandscape;

- (void) rotateToLandscapeRight;

- (void) prepareToAnimate;

@end