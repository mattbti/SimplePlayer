//
//  OpenTexture1Renderer.h
//  OSXGLEssentials
//
//  Created by Matthew Doig on 3/21/14.
//
//

#import "glUtil.h"
#import <Foundation/Foundation.h>

@interface OpenShadeRenderer : NSObject

@property (nonatomic, assign) float currentTime;
@property (nonatomic, assign) uint64_t startTime;

- (id) initWithDefaultFBO: (GLuint) defaultFBOName;
- (void) resizeWithWidth:(GLuint)width AndHeight:(GLuint)height;
- (void) render;
- (void) dealloc;
- (void) initCA;
- (void) initTN;

@end