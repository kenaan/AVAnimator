//
//  AVOfflineComposition.h
//  Created by Moses DeJong on 3/31/12.
//
//  License terms defined in License.txt.

#import "AVOfflineComposition.h"

#import "AutoPropertyRelease.h"

#import "CGFrameBuffer.h"

#import "AVMvidFileWriter.h"

#import "AVMvidFrameDecoder.h"

#import <QuartzCore/QuartzCore.h>

#define LOGGING

// Notification name constants

NSString * const AVOfflineCompositionCompletedNotification = @"AVOfflineCompositionCompletedNotification";

NSString * const AVOfflineCompositionFailedNotification = @"AVOfflineCompositionFailedNotification";

typedef enum
{
  AVOfflineCompositionClipTypeMvid = 0,
  AVOfflineCompositionClipTypeH264  
} AVOfflineCompositionClipType;

// Util object, one is created for each clip to be rendered in the composition

@interface AVOfflineCompositionClip : NSObject
{
  NSString   *m_clipSource;
  AVMvidFrameDecoder *m_mvidFrameDecoder;
  // FIXME: add h264 frame decoder
@public
  AVOfflineCompositionClipType clipType;
  NSInteger clipX;
  NSInteger clipY;
  NSInteger clipWidth;
  NSInteger clipHeight;
  float     clipStartSeconds;
  float     clipEndSeconds;
}

@property (nonatomic, copy) NSString *clipSource;

@property (nonatomic, retain) AVMvidFrameDecoder *mvidFrameDecoder;

+ (AVOfflineCompositionClip*) aVOfflineCompositionClip;

@end

// Private API

@interface AVOfflineComposition ()

// Read a plist from a resource file. Either a NSDictionary or NSArray

+ (id) readPlist:(NSString*)resFileName;

- (BOOL) parseToplevelProperties:(NSDictionary*)compDict;

- (BOOL) parseClipProperties:(NSDictionary*)compDict;

- (void) notifyCompositionCompleted;

- (void) notifyCompositionFailed;

- (NSString*) backgroundColorStr;

- (BOOL) composeFrames;

- (BOOL) composeClips:(NSUInteger)frame
        bitmapContext:(CGContextRef)bitmapContext;

- (void) closeClips;

@property (nonatomic, copy) NSString *errorString;

@property (nonatomic, copy) NSString *source;

@property (nonatomic, copy) NSString *destination;

@property (nonatomic, copy) NSArray *compClips;

@property (nonatomic, assign) float compDuration;

@property (nonatomic, assign) float compFPS;

@property (nonatomic, assign) float compFrameDuration;

@property (nonatomic, assign) NSUInteger numFrames;

@property (nonatomic, assign) CGSize compSize;

@end

// Implementation of AVOfflineComposition

@implementation AVOfflineComposition

@synthesize errorString = m_errorString;

@synthesize source = m_source;

@synthesize destination = m_destination;

@synthesize compClips = m_compClips;

@synthesize compDuration = m_compDuration;

@synthesize numFrames = m_numFrames;

@synthesize compFPS = m_compFPS;

@synthesize compFrameDuration = m_compFrameDuration;

@synthesize compSize = m_compSize;

// Constructor

+ (AVOfflineComposition*) aVOfflineComposition
{
  AVOfflineComposition *obj = [[[AVOfflineComposition alloc] init] autorelease];
  return obj;
}

- (void) dealloc
{
  if (self->m_backgroundColor) {
    CGColorRelease(self->m_backgroundColor);
  }
  [AutoPropertyRelease releaseProperties:self thisClass:AVOfflineComposition.class];
  [super dealloc];
}

// Initiate a composition operation given info about the composition
// contained in the indicated dictionary.

- (void) compose:(NSDictionary*)compDict
{
  BOOL worked;
  
  NSAssert(compDict, @"compDict must not be nil");

  worked = [self parseToplevelProperties:compDict];
  
  if (!worked) {
    [self notifyCompositionFailed];
    return;
  }
  
  worked = [self composeFrames];

  if (!worked) {
    [self notifyCompositionFailed];
    return;
  } else {
    // Deliver success notification
    [self notifyCompositionCompleted];
  }
  
  return;
}

+ (id) readPlist:(NSString*)resFileName
{
  NSData *plistData;  
  NSString *error;  
  NSPropertyListFormat format;  
  id plist;  
  
  NSString *resPath = [[NSBundle mainBundle] pathForResource:resFileName ofType:@""];  
  plistData = [NSData dataWithContentsOfFile:resPath];   
  
  plist = [NSPropertyListSerialization propertyListFromData:plistData mutabilityOption:NSPropertyListImmutable format:&format errorDescription:&error];
  if (!plist) {
    NSLog(@"Error reading plist from file '%s', error = '%s'", [resFileName UTF8String], [error UTF8String]);  
    [error release];  
  }
  return plist;  
}

- (CGColorRef) createCGColor:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
{
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGFloat components[4] = {red, green, blue, alpha};
  CGColorRef cgColor = CGColorCreate(colorSpace, components);
  CGColorSpaceRelease(colorSpace);
  return cgColor;
}

- (CGColorRef) createColorWithHexString:(NSString*)stringToConvert
{
  NSScanner *scanner = [NSScanner scannerWithString:stringToConvert];
  unsigned hex;
  if (![scanner scanHexInt:&hex]) return NULL;
  int r = (hex >> 16) & 0xFF;
  int g = (hex >> 8) & 0xFF;
  int b = (hex) & 0xFF;
  
  CGFloat redPercentage = r / 255.0f;
  CGFloat greenPercentage = g / 255.0f;
  CGFloat bluePercentage = b / 255.0f;
  CGFloat alphaPercentage = 1.0f;
  
  return [self createCGColor:redPercentage green:greenPercentage blue:bluePercentage alpha:alphaPercentage];
}

// Return the parsed core graphics color as a "#RRGGBBAA" string value

+ (NSString*) cgColorToString:(CGColorRef)cgColorRef
{
  const CGFloat *components = CGColorGetComponents(cgColorRef);
  int red = (int)(components[0] * 255);
  int green = (int)(components[1] * 255);
  int blue = (int)(components[2] * 255);
  int alpha = (int)(components[3] * 255);
  return [NSString stringWithFormat:@"#%0.2X%0.2X%0.2X%0.2X", red, green, blue, alpha];
}

- (NSString*) backgroundColorStr
{
  return [self.class cgColorToString:self->m_backgroundColor];
}

// Parse color from a string specification, must be "#RRGGBB" or "#RRGGBBAA"

- (CGColorRef) createParsedCGColor:(NSString*)colorSpec
{
  int len = [colorSpec length];
  if (len != 7 && len != 9) {
    self.errorString = @"CompBackgroundColor invalid";
    return NULL;
  }
  
  char c = (char) [colorSpec characterAtIndex:0];
  
  if (c != '#') {
    self.errorString = @"CompBackgroundColor invalid : must begin with #";
    return NULL;
  }
  
  NSString *stringNoPound = [colorSpec substringFromIndex:1];
  
  CGColorRef colorRef = [self createColorWithHexString:stringNoPound];
  
  if (colorRef == NULL) {
    self.errorString = @"CompBackgroundColor invalid";
    return NULL;
  }
  
  return colorRef;  
}

// Parse expected properties defined in the plist file and store them as properties of the
// composition object.

- (BOOL) parseToplevelProperties:(NSDictionary*)compDict
{
  self.errorString = nil;
  
  // Source is an optional string to indicate the plist data was parsed from
  
  self.source = [compDict objectForKey:@"Source"];
  
  // Destination is the output file name

  NSString *destination = [compDict objectForKey:@"Destination"];
  
  if (destination == nil) {
    self.errorString = @"Destination not found";
    return FALSE;
  }

  if ([destination length] == 0) {
    self.errorString = @"Destination invalid";
    return FALSE;
  }
  
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:destination];
  self.destination = tmpPath;
  
  // CompDurationSeconds indicates the total composition duration in floating point seconds
  
  NSNumber *compDurationSecondsNum = [compDict objectForKey:@"CompDurationSeconds"];
  float compDurationSeconds;

  if (compDurationSecondsNum == nil) {
    self.errorString = @"CompDurationSeconds not found";
    return FALSE;
  }
  
  compDurationSeconds = [compDurationSecondsNum floatValue];
  if (compDurationSeconds <= 0.0f) {
    self.errorString = @"CompDurationSeconds range";
    return FALSE;
  }
  
  self.compDuration = compDurationSeconds;
  
  // CompBackgroundColor defines a #RRGGBB string that indicates the background
  // color for the whole composition. By default, this color is black.
  
  NSString *bgColorStr = [compDict objectForKey:@"CompBackgroundColor"];
  
  if (bgColorStr == nil) {
    bgColorStr = @"#000000";
  }
  
  self->m_backgroundColor = [self createParsedCGColor:bgColorStr];
  
  if (self->m_backgroundColor == NULL) {
    return FALSE;
  }
  
  // CompFramesPerSecond is a floating point number that indicates how many frames per second
  // the resulting composition will be. This field is required.
  // Common Values: 1, 2, 15, 24, 29.97, 30, 48, 60
  
  NSNumber *compFramesPerSecondNum = [compDict objectForKey:@"CompFramesPerSecond"];
  float compFramesPerSecond;

  compFramesPerSecond = [compFramesPerSecondNum floatValue];

  self.compFPS = compFramesPerSecond;
  
  // Calculate total number of frames based on total duration and frame duration
  
  float frameDuration = 1.0 / compFramesPerSecond;
  self.compFrameDuration = frameDuration;
  int numFrames = (int) round(self.compDuration / frameDuration);
  self.numFrames = numFrames;
  
  // Parse CompWidth and CompHeight to define size of movie
  
  NSNumber *compWidthNum = [compDict objectForKey:@"CompWidth"];
  
  if (compWidthNum == nil) {
    self.errorString = @"CompWidth not found";
    return FALSE;
  }

  NSNumber *compHeightNum = [compDict objectForKey:@"CompHeight"];

  if (compHeightNum == nil) {
    self.errorString = @"CompHeight not found";
    return FALSE;
  }

  NSInteger compWidth = [compWidthNum intValue];
  NSInteger compHeight= [compHeightNum intValue];

  if (compWidth < 1) {
    self.errorString = @"CompWidth invalid";
    return FALSE;
  }

  if (compHeight < 1) {
    self.errorString = @"CompHeight invalid";
    return FALSE;
  }
  
  self.compSize = CGSizeMake(compWidth, compHeight);

  // Parse CompClips, this array of dicttionary property is optional

  [self parseClipProperties:compDict];
  
  return TRUE;
}

// Parse clip data from PLIST and setup objects that will read clip data
// from files.

- (BOOL) parseClipProperties:(NSDictionary*)compDict
{
  NSArray *compClips = [compDict objectForKey:@"CompClips"];
  
  NSMutableArray *mArr = [NSMutableArray array];
  
  int clipOffset = 0;
  for (NSDictionary *clipDict in compClips) {
    // Each element of the CompClips array is parsed and added to the
    // self.compClips as an instance of AVOfflineCompositionClip.
    
    AVOfflineCompositionClip *compClip = [AVOfflineCompositionClip aVOfflineCompositionClip];
    
    // ClipSource is a mvid or H264 movie that frames are loaded from
    
    NSString *clipSource = [clipDict objectForKey:@"ClipSource"];
    
    if (clipSource == nil) {
      self.errorString = @"ClipSource not found";
      return FALSE;
    }
    
    // ClipSource could indicate a resource file (the assumed default).
    
    NSString *resPath = [[NSBundle mainBundle] pathForResource:clipSource ofType:@""];
    
    if (resPath != nil) {
      // ClipSource is the name of a resource file
      clipSource = resPath;
    } else {
      // If ClipSource is not a resource file, check for a file with that name in the tmp dir
      NSString *tmpDir = NSTemporaryDirectory();
      NSString *tmpPath = [tmpDir stringByAppendingPathComponent:clipSource];
      if ([[NSFileManager defaultManager] fileExistsAtPath:tmpPath]) {
        clipSource = tmpPath;
      }
    }
    
    // ClipType is a string to indicate the type of movie clip
    
    NSString *clipTypeStr = [clipDict objectForKey:@"ClipType"];
    
    if (clipTypeStr == nil) {
      return FALSE;
    }
    
    AVOfflineCompositionClipType clipType;

    if ([clipTypeStr isEqualToString:@"mvid"]) {
      clipType = AVOfflineCompositionClipTypeMvid;
    } else if ([clipTypeStr isEqualToString:@"h264"]) {
      clipType = AVOfflineCompositionClipTypeH264;
    } else {
      self.errorString = @"ClipType unsupported";
      return FALSE;
    }
    
    // ClipX, ClipY : signed int
    
    NSNumber *clipXNum = [clipDict objectForKey:@"ClipX"];
    NSNumber *clipYNum = [clipDict objectForKey:@"ClipY"];
    
    if (clipXNum == nil) {
      self.errorString = @"ClipX not found";
      return FALSE;
    }
    if (clipYNum == nil) {
      self.errorString = @"ClipY not found";
      return FALSE;
    }
    
    NSInteger clipX = [clipXNum intValue];
    NSInteger clipY = [clipYNum intValue];
    
    // ClipWidth, ClipHeight unsigned int
    
    NSNumber *clipWidthNum = [clipDict objectForKey:@"ClipWidth"];
    NSNumber *clipHeightNum = [clipDict objectForKey:@"ClipHeight"];
    
    if (clipWidthNum == nil) {
      self.errorString = @"ClipWidth not found";
      return FALSE;
    }
    if (clipHeightNum == nil) {
      self.errorString = @"ClipHeight not found";
      return FALSE;
    }
    
    NSInteger clipWidth = [clipWidthNum intValue];
    NSInteger clipHeight = [clipHeightNum intValue];
    
    if (clipWidth <= 0) {
      self.errorString = @"ClipWidth invalid";
      return FALSE;
    }
    
    if (clipHeight <= 0) {
      self.errorString = @"ClipHeight invalid";
      return FALSE;
    }
    
    // ClipStartSeconds, ClipEndSeconds : float time values
    
    NSNumber *clipStartSecondsNum = [clipDict objectForKey:@"ClipStartSeconds"];
    NSNumber *clipEndSecondsNum = [clipDict objectForKey:@"ClipEndSeconds"];
    
    float clipStartSeconds = [clipStartSecondsNum floatValue];
    float clipEndSeconds = [clipEndSecondsNum floatValue];
    
    // Fill in fields of AVOfflineCompositionClip
    
    compClip.clipSource = clipSource;
    compClip->clipType = clipType;
    compClip->clipX = clipX;
    compClip->clipY = clipY;
    compClip->clipWidth = clipWidth;
    compClip->clipHeight = clipHeight;
    compClip->clipStartSeconds = clipStartSeconds;
    compClip->clipEndSeconds = clipEndSeconds;    

    if (clipType == AVOfflineCompositionClipTypeMvid) {
      AVMvidFrameDecoder *mvidFrameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
      
      BOOL worked = [mvidFrameDecoder openForReading:compClip.clipSource];
      if (worked == FALSE) {
        self.errorString = [NSString stringWithFormat:@"open of ClipSource file failed: %@", compClip.clipSource];
        return FALSE;
      }
      
      compClip.mvidFrameDecoder = mvidFrameDecoder;
    }
    
    // FIXME: add h264 support
    
    [mArr addObject:compClip];
    
    clipOffset++;
  }
  
  self.compClips = [NSArray arrayWithArray:mArr];
  
  return TRUE;
}

- (void) notifyCompositionCompleted
{
  [[NSNotificationCenter defaultCenter] postNotificationName:AVOfflineCompositionCompletedNotification
                                                      object:self];	
}

- (void) notifyCompositionFailed
{
  [[NSNotificationCenter defaultCenter] postNotificationName:AVOfflineCompositionFailedNotification
                                                      object:self];	
}

// Main compose frames operation, iterate over each frame, render specific views, then
// write each frame out to the .mvid movie file.

- (BOOL) composeFrames
{
  BOOL retcode = TRUE;
  BOOL worked;
  
  const NSUInteger maxFrame = self.numFrames;

  NSUInteger width = self.compSize.width;
  NSUInteger height = self.compSize.height;
  
  const uint32_t framebufferNumBytes = width * height * sizeof(uint32_t);
  
  // Allocate buffer that will contain the rendered frame for each time step
  
  CGFrameBuffer *cgFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24
                                                                         width:width
                                                                        height:height];
  
  if (cgFrameBuffer == nil) {
    return FALSE;
  }
  
  // Wrap the pixels in a bitmap context ref
  
  CGContextRef bitmapContext = [cgFrameBuffer createBitmapContext];

  if (bitmapContext == NULL) {
    return FALSE;
  }
  
  // Create output .mvid file writer
  
  AVMvidFileWriter *fileWriter = [AVMvidFileWriter aVMvidFileWriter];
  NSAssert(fileWriter, @"fileWriter");
  
  fileWriter.mvidPath = self.destination;
  fileWriter.bpp = 24;
  fileWriter.movieSize = self.compSize;

  fileWriter.frameDuration = self.compFrameDuration;
  fileWriter.totalNumFrames = maxFrame;

  //fileWriter.genAdler = TRUE;
  
  worked = [fileWriter open];
  if (worked == FALSE) {
    retcode = FALSE;
  }
  
  for (NSUInteger frame = 0; retcode && (frame < maxFrame); frame++) {
    // Clear the entire frame to the background color with a simple fill
    
    CGContextSetFillColorWithColor(bitmapContext, self->m_backgroundColor);
    CGContextFillRect(bitmapContext, CGRectMake(0, 0, width, height));
    
    // FIXME: iterate over contained images and render each one based on time settings
    
    worked = [self composeClips:frame bitmapContext:bitmapContext];
    if (worked == FALSE) {
      retcode = FALSE;
      break;
    }
    
    // Write frame buffer out to .mvid container
    
    worked = [fileWriter writeKeyframe:(char*)cgFrameBuffer.pixels bufferSize:framebufferNumBytes];
    
    if (worked == FALSE) {
      retcode = FALSE;
      break;
    }
  }
  
  [self closeClips];
  
  CGContextRelease(bitmapContext);
  
  worked = [fileWriter rewriteHeader];
  if (worked == FALSE) {
    retcode = FALSE;
  }
  
  [fileWriter close];
  
#ifdef LOGGING
  NSLog(@"Wrote comp file %@", fileWriter.mvidPath);
#endif // LOGGING
  
  return retcode;
}

// FIXME: initial round of looping over the clip info will parse a set of values
// into a struct that holds the parsed values and a ref to the opened clip
// data in the file.

// Iterate over each clip for a specific time and render clips that are visible.

- (BOOL) composeClips:(NSUInteger)frame
        bitmapContext:(CGContextRef)bitmapContext
{
  BOOL worked;
  float frameTime = frame * self.compFrameDuration;
  
  if (self.compClips == nil) {
    // No clips
    return TRUE;
  }
  
  int clipOffset = 0;
  for (AVOfflineCompositionClip *compClip in self.compClips) {
    // ClipSource is a mvid or H264 movie that frames are loaded from

    float clipStartSeconds = compClip->clipStartSeconds;
    float clipEndSeconds = compClip->clipEndSeconds;
    
    // Render a specific clip if it the frame time is in [START, END] time bounds    
    
    if (frameTime >= clipStartSeconds && frameTime <= clipEndSeconds) {
      // Render specific frame from this clip
      
#ifdef LOGGING
      NSLog(@"Found clip active for comp time %0.2f, clip %d [%0.2f, %0.2f]", frameTime, clipOffset, clipStartSeconds, clipEndSeconds);
#endif // LOGGING
      
      float clipTime = frameTime - clipStartSeconds;
      
      // FIXME: clip framerate must be used to calculate the frame offset of a specific
      // frame. But, this value needs to be scaled to the display time, because a longer
      // display time will modify the effective framerate. For example, if a clip is
      // played twice as long, its framerate will be reduced by half.
      
      NSUInteger clipFrame = (NSUInteger) round(clipTime / self.compFrameDuration);
      
      CGImageRef cgImageRef = NULL;
      
      if (compClip->clipType == AVOfflineCompositionClipTypeMvid) {
        AVMvidFrameDecoder *mvidFrameDecoder = compClip.mvidFrameDecoder;
        
        worked = [mvidFrameDecoder allocateDecodeResources];
        
        if (worked == FALSE) {
          return FALSE;
        }
        
        // FIXME: would be better if this API returned a CGImageRef but a UIImage
        // is not actually used for anything so it should be thread safe.
        
        UIImage *image = [mvidFrameDecoder advanceToFrame:clipFrame];
        
        cgImageRef = image.CGImage;
      } else if (compClip->clipType == AVOfflineCompositionClipTypeH264) {
        // FIXME: H.264 support
        assert(0);
      } else {
        assert(0);
      }
        
      // Render frame by painting frame image into a specific rectangle in the framebuffer
      
      CGRect bounds = CGRectMake(compClip->clipX, compClip->clipY, compClip->clipWidth, compClip->clipHeight );
      
      CGContextDrawImage(bitmapContext, bounds, cgImageRef);
    }
    
    clipOffset++;
  }
  
  return TRUE;
}

// Close resources associated with each open clip

- (void) closeClips
{
  // Clips are automatically cleaned up when last ref is dropped
  
  self.compClips = nil;
}

@end // AVOfflineComposition


// Util object, one is created for each clip to be rendered in the composition

@implementation AVOfflineCompositionClip

@synthesize clipSource = m_clipSource;

@synthesize mvidFrameDecoder = m_mvidFrameDecoder;

+ (AVOfflineCompositionClip*) aVOfflineCompositionClip
{
  AVOfflineCompositionClip *obj = [[AVOfflineCompositionClip alloc] init];
  return [obj autorelease];
}

- (void) dealloc
{
  [AutoPropertyRelease releaseProperties:self thisClass:AVOfflineCompositionClip.class];
  [super dealloc];
}

@end
