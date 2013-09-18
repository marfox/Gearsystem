/*
 * Gearboy - Nintendo Game Boy Emulator
 * Copyright (C) 2012  Ignacio Sanchez
 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see http://www.gnu.org/licenses/
 *
 */

#import <GLKit/GLKit.h>
#import "Emulator.h"
#include "inputmanager.h"

const float kMixFrameAlpha = 0.35f;
const float kGB_Width = 160.0f;
const float kGB_Height = 144.0f;
const float kGB_TexWidth = kGB_Width / 256.0f;
const float kGB_TexHeight = kGB_Height / 256.0f;
const GLfloat box[] = {0.0f, kGB_Height, 1.0f, kGB_Width,kGB_Height, 1.0f, 0.0f, 0.0f, 1.0f, kGB_Width, 0.0f, 1.0f};
const GLfloat tex[] = {0.0f, kGB_TexHeight, kGB_TexWidth, kGB_TexHeight, 0.0f, 0.0f, kGB_TexWidth, 0.0f};

@implementation Emulator

@synthesize multiplier, retina, iPad;

-(id)init
{
    if (self = [super init])
    {
        firstFrame = YES;
        
        theGearsystemCore = new GearsystemCore();
        theGearsystemCore->Init();
        
        theInput = new EmulatorInput(self);
        theInput->Init();
        initialized = NO;
        theFrameBuffer = new GS_Color[GS_SMS_WIDTH * GS_SMS_HEIGHT];
        theTexture = new GS_Color[256 * 256];
        
        for (int y = 0; y < GS_SMS_HEIGHT; ++y)
        {
            for (int x = 0; x < GS_SMS_WIDTH; ++x)
            {
                int pixel = (y * GS_SMS_WIDTH) + x;
                theFrameBuffer[pixel].red = theFrameBuffer[pixel].green = theFrameBuffer[pixel].blue = 0x00;
                theFrameBuffer[pixel].alpha = 0xFF;
            }
        }
        
        for (int y = 0; y < 256; ++y)
        {
            for (int x = 0; x < 256; ++x)
            {
                int pixel = (y * 256) + x;
                theTexture[pixel].red = theTexture[pixel].green = theTexture[pixel].blue = 0x00;
                theTexture[pixel].alpha = 0xFF;
            }
        }
    }
    return self;
}

-(void)dealloc
{
    theGearsystemCore->SaveRam();
    SafeDeleteArray(theTexture);
    SafeDeleteArray(theFrameBuffer);
    SafeDelete(theGearsystemCore);
    [self shutdownGL];
}

-(void)shutdownGL
{
    glDeleteTextures(1, &accumulationTexture);
    glDeleteTextures(1, &GBTexture);
    glDeleteFramebuffers(1, &accumulationFramebuffer);
    initialized = NO;
}

-(void)update
{
    InputManager::Instance().Update();
    
    theGearsystemCore->RunToVBlank(theFrameBuffer);
    
    for (int y = 0; y < GS_SMS_HEIGHT; ++y)
    {
        int y_256 = y * 256;
        int y_gb_width = y * GS_SMS_WIDTH;
        for (int x = 0; x < GS_SMS_WIDTH; ++x)
        {
            theTexture[y_256 + x] = theFrameBuffer[y_gb_width + x];
        }
    }
}

-(void)draw
{
    if (!initialized)
    {
        initialized = YES;
        [self initGL];     
    }
    
    [self renderFrame];
}

-(void)initGL
{
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &iOSFrameBuffer);
    
    glGenFramebuffers(1, &accumulationFramebuffer);
    glGenTextures(1, &accumulationTexture);
    glGenTextures(1, &GBTexture);
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    
    glVertexPointer(3, GL_FLOAT, 0, box);
    glTexCoordPointer(2, GL_FLOAT, 0, tex);
    
    glClearColor(0.0, 0.0, 0.0, 0.0);
    
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, GBTexture);
    [self setupTextureWithData: (GLvoid*) theTexture];

    glBindFramebuffer(GL_FRAMEBUFFER, accumulationFramebuffer);
    glBindTexture(GL_TEXTURE_2D, accumulationTexture);
    [self setupTextureWithData: NULL];
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, accumulationTexture, 0);  
}

-(void)renderFrame
{
    glBindFramebuffer(GL_FRAMEBUFFER, iOSFrameBuffer);
    glBindTexture(GL_TEXTURE_2D, GBTexture);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 256, 256, GL_RGBA, GL_UNSIGNED_BYTE, (GLvoid*) theTexture);
    [self renderQuadWithViewportWidth:(80 * multiplier) andHeight:(72 * multiplier) andMirrorY:NO];
}



-(void)setupTextureWithData: (GLvoid*) data
{
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 256, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
}

-(void)renderQuadWithViewportWidth: (int)viewportWidth andHeight: (int)viewportHeight andMirrorY: (BOOL) mirrorY
{
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    if (mirrorY)
        glOrthof(0.0f, kGB_Width, 0.0f, kGB_Height, -1.0f, 1.0f);
    else
        glOrthof(0.0f, kGB_Width, kGB_Height, 0.0f, -1.0f, 1.0f);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glViewport(0, 0, viewportWidth, viewportHeight);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

-(void)loadRomWithPath: (NSString *)filePath
{
    theGearsystemCore->SaveRam();
    theGearsystemCore->LoadROM([filePath UTF8String]);
    theGearsystemCore->LoadRam();
    firstFrame = YES;
}

-(void)keyPressed: (GS_Keys)key
{
    theGearsystemCore->KeyPressed(Joypad_1, key);
}

-(void)keyReleased: (GS_Keys)key
{
    theGearsystemCore->KeyReleased(Joypad_1, key);
}

-(void)pause
{
    theGearsystemCore->Pause(true);
}

-(void)resume
{
    theGearsystemCore->Pause(false);
}

-(BOOL)paused
{
    return theGearsystemCore->IsPaused();
}

-(void)reset
{
    theGearsystemCore->SaveRam();
    theGearsystemCore->ResetROM();
    theGearsystemCore->LoadRam();
    firstFrame = YES;
}

-(void)save
{
    theGearsystemCore->SaveRam();
}

@end