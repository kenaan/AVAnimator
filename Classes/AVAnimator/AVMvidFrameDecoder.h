//
//  AVMvidFrameDecoder.h
//  QTFileParserApp
//
//  Created by Moses DeJong on 4/23/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AVFrameDecoder.h"
#import "maxvid_file.h"

@interface AVMvidFrameDecoder : AVFrameDecoder {
  NSString *m_filePath;
  MVFile *m_mvFile;
	BOOL m_isOpen;  
  NSData *m_mappedData;
  
  CGFrameBuffer *m_currentFrameBuffer;  
	NSArray *m_cgFrameBuffers;
  
	int frameIndex;
  BOOL m_resourceUsageLimit;
}

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSData *mappedData;
@property (nonatomic, retain) CGFrameBuffer *currentFrameBuffer;
@property (nonatomic, copy) NSArray *cgFrameBuffers;

+ (AVMvidFrameDecoder*) aVMvidFrameDecoder;

// Open resource identified by path

- (BOOL) openForReading:(NSString*)path;

// Close resource opened earlier

- (void) close;

// Reset current frame index to -1, before the first frame

- (void) rewind;

// Advance the current frame index to the indicated frame index and store result in nextFrameBuffer

- (UIImage*) advanceToFrame:(NSUInteger)newFrameIndex;

// A frame decoder may be asked to limit memory usage or deallocate
// resources when it is not being actively used. When enabled, the
// frame decoder should deallocate memory where possible.

- (void) resourceUsageLimit:(BOOL)enabled;

// Return the current frame buffer, this is the buffer that was most recently written to via
// a call to advanceToFrame. Returns nil on init or after a rewind operation.

- (CGFrameBuffer*) currentFrameBuffer;

// Properties

// Dimensions of each frame
- (NSUInteger) width;
- (NSUInteger) height;

// True when resource has been opened via openForReading
- (BOOL) isOpen;

// Total frame count
- (NSUInteger) numFrames;

// Current frame index, can be -1 at init or after rewind
- (NSInteger) frameIndex;

// Time each frame shold be displayed
- (NSTimeInterval) frameDuration;

@end
