//
//  ICGVideoTrimmerView.m
//  ICGVideoTrimmer
//
//  Created by Huong Do on 1/18/15.
//  Copyright (c) 2015 ichigo. All rights reserved.
//

#import "ICGVideoTrimmerView.h"
#import "ICGThumbView.h"
#import "ICGRulerView.h"



@interface HitTestView : UIView
@property (assign, nonatomic) UIEdgeInsets hitTestEdgeInsets;
- (BOOL)pointInside:(CGPoint)point;

@end

@implementation HitTestView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    return [self pointInside:point];
}

- (BOOL)pointInside:(CGPoint)point
{
    CGRect relativeFrame = self.bounds;
    CGRect hitFrame = UIEdgeInsetsInsetRect(relativeFrame, _hitTestEdgeInsets);
    return CGRectContainsPoint(hitFrame, point);
}

@end


@interface ICGVideoTrimmerView() <UIScrollViewDelegate>

@property (strong, nonatomic) UIView *contentView;
@property (strong, nonatomic) UIView *frameView;
@property (strong, nonatomic) UIScrollView *scrollView;
@property (strong, nonatomic) AVAssetImageGenerator *imageGenerator;

@property (strong, nonatomic) HitTestView *leftOverlayView;
@property (strong, nonatomic) HitTestView *rightOverlayView;
@property (strong, nonatomic) ICGThumbView *leftThumbView;
@property (strong, nonatomic) ICGThumbView *rightThumbView;

@property (assign, nonatomic) BOOL isDraggingRightOverlayView;
@property (assign, nonatomic) BOOL isDraggingLeftOverlayView;


@property (strong, nonatomic) UIView *trackerView;
@property (strong, nonatomic) UIView *blueView;

@property (strong, nonatomic) UILabel *timeCode;

// trackerHandle
@property (strong, nonatomic) UIView *tracker;
@property (strong, nonatomic) UIView *trackerHandle;
@property (strong, nonatomic) UIView *topBorder;
@property (strong, nonatomic) UIView *bottomBorder;

@property (strong, nonatomic) UIPanGestureRecognizer *panGestureRecognizer;
@property (strong, nonatomic) UILongPressGestureRecognizer *longPanGestureRecognizer;

// setup
@property (strong,nonatomic) NSTimer *timer;          // triggers the long press during pan
@property (strong,nonatomic) UIView *longPressView;   // need this to track long press state


@property (nonatomic) CGFloat startTime;
@property (nonatomic) CGFloat endTime;

@property (nonatomic) CGFloat widthPerSecond;
@property (nonatomic) int trackerHandleHeight;

@property (nonatomic) CGPoint leftStartPoint;
@property (nonatomic) CGPoint rightStartPoint;
@property (nonatomic) CGFloat overlayWidth;

@property (nonatomic) CGFloat prevTrackerTime;


@end

@implementation ICGVideoTrimmerView

#pragma mark - Initiation

- (instancetype)initWithFrame:(CGRect)frame
{
    NSAssert(NO, nil);
    @throw nil;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    _themeColor = [UIColor lightGrayColor];
    return [super initWithCoder:aDecoder];
}

- (instancetype)initWithAsset:(AVAsset *)asset
{
    return [self initWithFrame:CGRectZero asset:asset];
}

- (instancetype)initWithFrame:(CGRect)frame asset:(AVAsset *)asset
{
    self = [super initWithFrame:frame];
    if (self) {
        _asset = asset;
        [self resetSubviews];
    }
    return self;
}

- (void)setThemeColor:(UIColor *)themeColor {
    _themeColor = themeColor;

    [self.bottomBorder setBackgroundColor:_themeColor];
    [self.topBorder setBackgroundColor:_themeColor];
    self.leftThumbView.color = _themeColor;
    self.rightThumbView.color = _themeColor;
}


#pragma mark - Private methods

//- (UIColor *)themeColor
//{
//    return _themeColor ?: [UIColor lightGrayColor];
//}

- (CGFloat)maxLength
{
    return _maxLength ?: 15;
}

- (CGFloat)minLength
{
    return _minLength ?: 3;
}

- (UIColor *)trackerColor
{
    return _trackerColor ?: [UIColor whiteColor];
}

- (UIColor *) trackerHandleColor
{
    return _trackerHandleColor ?: [UIColor whiteColor];
}

- (Boolean) showTrackerHandle
{
    return _showTrackerHandle ?: NO;
}

- (CGFloat)borderWidth
{
    return _borderWidth ?: 1;
}

- (CGFloat)thumbWidth
{
    return _thumbWidth ?: 10;
}

- (NSInteger) rulerLabelInterval
{
    return _rulerLabelInterval ?: 5;
}

#define EDGE_EXTENSION_FOR_THUMB 30
- (void)resetSubviews
{
    self.trackerHandleHeight = 20;
    CALayer *sideMaskingLayer = [CALayer new];
    sideMaskingLayer.backgroundColor = [UIColor blackColor].CGColor;
    sideMaskingLayer.frame = CGRectMake(0, -30, self.frame.size.width, self.frame.size.height + 40);
    self.layer.mask = sideMaskingLayer;
    
    [self setBackgroundColor:[UIColor clearColor]];
    
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.frame),
                                                                     CGRectGetHeight(self.frame) - self.trackerHandleHeight)];
    [self addSubview:self.scrollView];
    [self.scrollView setDelegate:self];
    [self.scrollView setShowsHorizontalScrollIndicator:NO];
    
    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.scrollView.frame), CGRectGetHeight(self.scrollView.frame))];
    [self.contentView setUserInteractionEnabled:YES];
    [self.scrollView setContentSize:self.contentView.frame.size];
    [self.scrollView addSubview:self.contentView];
    
    CGFloat ratio = self.showsRulerView ? 0.7 : 1.0;
    self.frameView = [[UIView alloc] initWithFrame:CGRectMake(self.thumbWidth, 0, CGRectGetWidth(self.contentView.frame)-(2*self.thumbWidth), CGRectGetHeight(self.contentView.frame)*ratio)];
//    [self.frameView.layer setMasksToBounds:YES];
    [self.contentView addSubview:self.frameView];
    
    [self addFrames];
    
    if (self.showsRulerView) {
        CGRect rulerFrame = CGRectMake(0, CGRectGetHeight(self.contentView.frame)*0.7, CGRectGetWidth(self.contentView.frame)+self.thumbWidth, CGRectGetHeight(self.contentView.frame)*0.3);
        ICGRulerView *rulerView = [[ICGRulerView alloc] initWithFrame:rulerFrame widthPerSecond:self.widthPerSecond themeColor:self.themeColor labelInterval:self.rulerLabelInterval];
        [self.contentView addSubview:rulerView];
    }
    
    // add borders
    self.topBorder = [[UIView alloc] init];
    [self.topBorder setBackgroundColor:self.themeColor];
    [self addSubview:self.topBorder];
    
    self.bottomBorder = [[UIView alloc] init];
    [self.bottomBorder setBackgroundColor:self.themeColor];
    [self addSubview:self.bottomBorder];
    
    // width for left and right overlay views
    self.overlayWidth =  CGRectGetWidth(self.frame) - (self.minLength * self.widthPerSecond);
    
    // add left overlay view
    self.leftOverlayView = [[HitTestView alloc] initWithFrame:CGRectMake(self.thumbWidth - self.overlayWidth, 0, self.overlayWidth, CGRectGetHeight(self.frameView.frame))];
    self.leftOverlayView.hitTestEdgeInsets = UIEdgeInsetsMake(0, 0, 0, -(EDGE_EXTENSION_FOR_THUMB));
    CGRect leftThumbFrame = CGRectMake(self.overlayWidth-self.thumbWidth, 0, self.thumbWidth, CGRectGetHeight(self.frameView.frame));
    if (self.leftThumbImage) {
        self.leftThumbView = [[ICGThumbView alloc] initWithFrame:leftThumbFrame thumbImage:self.leftThumbImage];
    } else {
        self.leftThumbView = [[ICGThumbView alloc] initWithFrame:leftThumbFrame color:self.themeColor right:NO];
    }
  
    // init tracker
//    self.trackerView = [[UIView alloc] initWithFrame:CGRectMake(self.thumbWidth, -5, 3, CGRectGetHeight(self.frameView.frame) + 10)];
//    self.trackerView.backgroundColor = self.trackerColor;
//    self.trackerView.layer.masksToBounds = true;
//    self.trackerView.layer.cornerRadius = 2;
//    [self addSubview:self.trackerView];
  
    self.trackerView = [[UIView alloc] initWithFrame:CGRectMake(self.thumbWidth - self.trackerHandleHeight / 2, 0, 20, CGRectGetHeight(self.frameView.frame) + self.trackerHandleHeight)];
    
    [self.trackerView setUserInteractionEnabled:YES];
//    self.trackerView.layer.cornerRadius = 2;
    
    self.blueView = [[UIView alloc] initWithFrame:CGRectMake(0, -30, 50, 30)];
    self.blueView.layer.cornerRadius = 5;
    [self.blueView setBackgroundColor:[UIColor colorWithWhite:0 alpha:0.8]];
    self.blueView.hidden = TRUE;
    
  // timeCode label
    self.timeCode = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 50, 30)];
    [self.timeCode setTextColor:[UIColor whiteColor]];
    
    [self.blueView addSubview:self.timeCode];
    
    self.tracker = [[UIView alloc] initWithFrame:CGRectMake(self.thumbWidth, 0, 3, CGRectGetHeight(self.frameView.frame))];
    self.tracker.backgroundColor = self.trackerColor;
    self.tracker.layer.cornerRadius = 2;
    [self.tracker setUserInteractionEnabled:YES];
  
    self.trackerHandle = [[UIView alloc] initWithFrame:CGRectMake(self.thumbWidth / 2, CGRectGetHeight(self.frameView.frame), self.trackerHandleHeight, self.trackerHandleHeight)];
    [self.trackerHandle.layer setMasksToBounds:YES];
    [self.trackerHandle.layer setCornerRadius:10];
    self.trackerHandle.backgroundColor = self.trackerHandleColor;
    [self.trackerHandle setUserInteractionEnabled:YES];
    
    [self.trackerView addSubview:self.tracker];
    [self.trackerView addSubview:self.blueView];
  
    if (self.showTrackerHandle) {
        [self.trackerView addSubview: self.trackerHandle];
    }
    
    [self addSubview:self.trackerView];
  
    [self.leftThumbView.layer setMasksToBounds:YES];
    [self.leftOverlayView addSubview:self.leftThumbView];
    [self.leftOverlayView setUserInteractionEnabled:YES];
    [self.leftOverlayView setBackgroundColor:[UIColor colorWithWhite:0 alpha:0.8]];
    [self addSubview:self.leftOverlayView];
    
    // add right overlay view
    CGFloat rightViewFrameX = CGRectGetWidth(self.frameView.frame) < CGRectGetWidth(self.frame) ? CGRectGetMaxX(self.frameView.frame) : CGRectGetWidth(self.frame) - self.thumbWidth;
    self.rightOverlayView = [[HitTestView alloc] initWithFrame:CGRectMake(rightViewFrameX, 0, self.overlayWidth, CGRectGetHeight(self.frameView.frame))];
    self.rightOverlayView.hitTestEdgeInsets = UIEdgeInsetsMake(0, -(EDGE_EXTENSION_FOR_THUMB), 0, 0);
    
    if (self.rightThumbImage) {
        self.rightThumbView = [[ICGThumbView alloc] initWithFrame:CGRectMake(0, 0, self.thumbWidth, CGRectGetHeight(self.frameView.frame)) thumbImage:self.rightThumbImage];
    } else {
        self.rightThumbView = [[ICGThumbView alloc] initWithFrame:CGRectMake(0, 0, self.thumbWidth, CGRectGetHeight(self.frameView.frame)) color:self.themeColor right:YES];
    }
    [self.rightThumbView.layer setMasksToBounds:YES];
    [self.rightOverlayView addSubview:self.rightThumbView];
    [self.rightOverlayView setUserInteractionEnabled:YES];
    [self.rightOverlayView setBackgroundColor:[UIColor colorWithWhite:0 alpha:0.8]];
    [self addSubview:self.rightOverlayView];
    
    
    UIPanGestureRecognizer *panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveOverlayView:)];
    [self addGestureRecognizer:panGestureRecognizer];
  
    self.panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleTrackerPan:)];

    [self.panGestureRecognizer locationInView: self.trackerView];
    [self.trackerView addGestureRecognizer:self.panGestureRecognizer];
  
    self.longPanGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressGestureRecognizer:)];
    [self addGestureRecognizer: self.longPanGestureRecognizer];
  
    [self updateBorderFrames];
    [self notifyDelegateOfDidChange];
}

- (void)setTimeCodeText: (CGFloat) time {
    self.blueView.hidden = FALSE;
    self.timeCode.text =  [self timeFormatted:roundf(time)];
}

- (void)clearTimeCodeText {
    self.timeCode.text = @"";
    self.blueView.hidden = TRUE;
}

- (void)startTimer:(UIView *)view {
    if (self.longPressView) return;
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self
                                                selector:@selector(longPressTimer:)
                                                userInfo:@{ @"view": view} repeats:NO];
}

- (void)longPressTimer:(NSTimer *)timer {
    self.longPressView = timer.userInfo[@"view"];
    [self longPressBegan: CGPointZero];
}

- (void)longPressBegan: (CGPoint) point {
    NSLog(@"long press began x: %f, y: %f ", point.x, point.y);

    CGRect longPressFrame = self.longPressView.frame;
    longPressFrame.origin.x += point.x - self.trackerHandleHeight / 2;
    self.trackerView.frame = longPressFrame;
  
    CGFloat time = (longPressFrame.origin.x - self.thumbWidth + self.scrollView.contentOffset.x + self.trackerHandleHeight) / self.widthPerSecond;
  
    NSLog(@"long press, go to: %.2f", time);
    
    [self setTimeCodeText:time];
    [self notifyDelegateOfCurrentPosition:time];
}

- (void)longPressEnded {
    self.longPressView = nil;
    NSLog(@"long press ended");
    [self clearTimeCodeText];
}

- (void)longPressGestureRecognizer:(UILongPressGestureRecognizer *)gestureRecognizer {

    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        self.longPressView = gestureRecognizer.view;
        CGPoint coords = [gestureRecognizer locationInView:gestureRecognizer.view];
        [self longPressBegan:coords];
    } else if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [self longPressEnded];
    }
}

- (void)updateBorderFrames {
    CGFloat height = self.borderWidth;
    [self.topBorder setFrame:CGRectMake(CGRectGetMaxX(self.leftOverlayView.frame), 0, CGRectGetMinX(self.rightOverlayView.frame)-CGRectGetMaxX(self.leftOverlayView.frame), height)];
    [self.bottomBorder setFrame:CGRectMake(CGRectGetMaxX(self.leftOverlayView.frame), CGRectGetHeight(self.frameView.frame)-height, CGRectGetMinX(self.rightOverlayView.frame)-CGRectGetMaxX(self.leftOverlayView.frame), height)];
}

- (void)handleTrackerPan: (UIGestureRecognizer *) recognizer {
  if (recognizer.state == UIGestureRecognizerStateBegan) {
    NSLog(@"Begin gesture tracker pan");
  } else if (recognizer.state == UIGestureRecognizerStateEnded) {
    NSLog(@"End gesture tracker pan");
    [self clearTimeCodeText];
  }else if ( recognizer.state == UIGestureRecognizerStateChanged){
    CGPoint point = [self.panGestureRecognizer locationInView:self.trackerView];

    CGRect trackerFrame = self.trackerView.frame;
    trackerFrame.origin.x += point.x - self.trackerHandleHeight / 2;
    self.trackerView.frame = trackerFrame;

    CGFloat time = (trackerFrame.origin.x - self.thumbWidth + self.scrollView.contentOffset.x + self.trackerHandleHeight) / self.widthPerSecond;
    NSLog(@"Handling tracker time: %.2f", time);
    
    [self setTimeCodeText:time];
    [self notifyDelegateOfCurrentPosition:time];
  }
}

- (void)moveOverlayView:(UIPanGestureRecognizer *)gesture
{
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        {
            [self startTimer:gesture.view];
            BOOL isRight =  [_rightOverlayView pointInside:[gesture locationInView:_rightOverlayView]];
            BOOL isLeft  =  [_leftOverlayView pointInside:[gesture locationInView:_leftOverlayView]];
            
            if (isRight){
                self.rightStartPoint = [gesture locationInView:self];
                _isDraggingRightOverlayView = YES;
                _isDraggingLeftOverlayView = NO;
            }
            else if (isLeft){
                self.leftStartPoint = [gesture locationInView:self];
                _isDraggingRightOverlayView = NO;
                _isDraggingLeftOverlayView = YES;
                
            }
            
        }    break;
        case UIGestureRecognizerStateChanged:
        {
            [self startTimer:gesture.view];
            CGPoint point = [gesture locationInView:self];
            //------------------------------------------------------------------------------------------------------------
            // Right
            if (_isDraggingRightOverlayView){
                
                CGFloat deltaX = point.x - self.rightStartPoint.x;
                
                CGPoint center = self.rightOverlayView.center;
                center.x += deltaX;
                CGFloat newRightViewMidX = center.x;
                CGFloat minX = CGRectGetMaxX(self.leftOverlayView.frame) + self.minLength * self.widthPerSecond;
                CGFloat maxX = CMTimeGetSeconds([self.asset duration]) <= self.maxLength + 0.5 ? CGRectGetMaxX(self.frameView.frame) : CGRectGetWidth(self.frame) - self.thumbWidth;
                if (newRightViewMidX - self.overlayWidth/2 < minX) {
                    newRightViewMidX = minX + self.overlayWidth/2;
                } else if (newRightViewMidX - self.overlayWidth/2 > maxX) {
                    newRightViewMidX = maxX + self.overlayWidth/2;
                }
                
                self.rightOverlayView.center = CGPointMake(newRightViewMidX, self.rightOverlayView.center.y);
                self.rightStartPoint = point;
            }
            else if (_isDraggingLeftOverlayView){
                
                //------------------------------------------------------------------------------------------------------------
                // Left
                CGFloat deltaX = point.x - self.leftStartPoint.x;
                
                CGPoint center = self.leftOverlayView.center;
                center.x += deltaX;
                CGFloat newLeftViewMidX = center.x;
                CGFloat maxWidth = CGRectGetMinX(self.rightOverlayView.frame) - (self.minLength * self.widthPerSecond);
                CGFloat newLeftViewMinX = newLeftViewMidX - self.overlayWidth/2;
                if (newLeftViewMinX < self.thumbWidth - self.overlayWidth) {
                    newLeftViewMidX = self.thumbWidth - self.overlayWidth + self.overlayWidth/2;
                } else if (newLeftViewMinX + self.overlayWidth > maxWidth) {
                    newLeftViewMidX = maxWidth - self.overlayWidth / 2;
                }
                
                self.leftOverlayView.center = CGPointMake(newLeftViewMidX, self.leftOverlayView.center.y);
                self.leftStartPoint = point;
            }
            //------------------------------------------------------------------------------------------------------------
            
            
            
            [self updateBorderFrames];
            [self notifyDelegateOfDidChange];
            
            break;
        }
        case UIGestureRecognizerStateEnded:
        {
            if (self.longPressView) {
                [self longPressEnded];
            } else {
                [self.timer invalidate];
            }
            [self notifyDelegateOfEndEditing];
        }
            
        default:
            break;
    }
}

- (void)seekToTime:(CGFloat) time
{
//    [self clearTimeCodeText];
    CGFloat duration = fabs(_prevTrackerTime - time);
    BOOL animate = (duration>1) ?  NO : YES;
    _prevTrackerTime = time;
    
    CGFloat posToMove = time * self.widthPerSecond + self.thumbWidth - self.scrollView.contentOffset.x - self.trackerHandleHeight;
    
    CGRect trackerFrame = self.trackerView.frame;
    trackerFrame.origin.x = posToMove;
    if (animate){
        [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.trackerView.frame = trackerFrame;
        } completion:nil ];
    }
    else{
        self.trackerView.frame = trackerFrame;
    }
}

- (void)hideTracker:(BOOL)flag
{
    if ( flag == YES ){
        self.trackerView.hidden = YES;
    }
    else{
        self.trackerView.alpha = 0;
        self.trackerView.hidden = NO;
        [UIView animateWithDuration:.3 animations:^{
            self.trackerView.alpha = 1;
        }];
    }
}

- (void)notifyDelegateOfCurrentPosition:(CGFloat)time {
  if([self.delegate respondsToSelector:@selector(trimmerView:currentPosition:)])
  {
    NSLog(@"notfiying of current position %f", time);
    [self.delegate trimmerView:self currentPosition:time];
  }
}

- (void)notifyDelegateOfDidChange
{
    NSLog(@"leftOverlayView:%f , rightOverlayView:%f contentOffset.x:%@", CGRectGetMaxX(self.leftOverlayView.frame) , CGRectGetMaxX(self.rightOverlayView.frame) , @(self.scrollView.contentOffset.x));
    
    
    CGFloat start = CGRectGetMaxX(self.leftOverlayView.frame) / self.widthPerSecond + (self.scrollView.contentOffset.x -self.thumbWidth) / self.widthPerSecond;
    CGFloat end = CGRectGetMinX(self.rightOverlayView.frame) / self.widthPerSecond + (self.scrollView.contentOffset.x - self.thumbWidth) / self.widthPerSecond;
    
    if (!self.trackerView.hidden && start != self.startTime) {
        [self seekToTime:start]; // why ?
    }
    
    if (start==self.startTime && end==self.endTime){
        // thumb events may fire multiple times with the same value, so we detect them and ignore them.
        NSLog(@"no change");
        return;
    }
    
    self.startTime = start;
    self.endTime = end;
    [self clearTimeCodeText];
  
    if([self.delegate respondsToSelector:@selector(trimmerView:didChangeLeftPosition:rightPosition:)])
    {
        [self.delegate trimmerView:self didChangeLeftPosition:self.startTime rightPosition:self.endTime];
    }
}

-(void) notifyDelegateOfEndEditing
{
    if([self.delegate respondsToSelector:@selector(trimmerViewDidEndEditing:)])
    {
        [self.delegate trimmerViewDidEndEditing:self];
    }
}

- (void)addFrames
{
    self.imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:self.asset];
    self.imageGenerator.appliesPreferredTrackTransform = YES;
    if ([self isRetina]){
        self.imageGenerator.maximumSize = CGSizeMake(CGRectGetWidth(self.frameView.frame)*2, CGRectGetHeight(self.frameView.frame)*2);
    } else {
        self.imageGenerator.maximumSize = CGSizeMake(CGRectGetWidth(self.frameView.frame), CGRectGetHeight(self.frameView.frame));
    }
    
    CGFloat picWidth = 0;
    
    // First image
    NSError *error;
    CMTime actualTime;
    CGImageRef halfWayImage = [self.imageGenerator copyCGImageAtTime:kCMTimeZero actualTime:&actualTime error:&error];
    UIImage *videoScreen;
    if ([self isRetina]){
        videoScreen = [[UIImage alloc] initWithCGImage:halfWayImage scale:2.0 orientation:UIImageOrientationUp];
    } else {
        videoScreen = [[UIImage alloc] initWithCGImage:halfWayImage];
    }
    if (halfWayImage != NULL) {
        UIImageView *tmp = [[UIImageView alloc] initWithImage:videoScreen];
        CGRect rect = tmp.frame;
        rect.size.width = videoScreen.size.width;
        tmp.frame = rect;
        [self.frameView addSubview:tmp];
        picWidth = tmp.frame.size.width;
        CGImageRelease(halfWayImage);
    }
    
    Float64 duration = CMTimeGetSeconds([self.asset duration]);
    CGFloat screenWidth = CGRectGetWidth(self.frame) - 2*self.thumbWidth; // quick fix to make up for the width of thumb views
    NSInteger actualFramesNeeded;
    
    CGFloat factor = (duration / self.maxLength);
    factor = (factor < 1 ? 1 : factor);
    CGFloat frameViewFrameWidth = factor * screenWidth;
    [self.frameView setFrame:CGRectMake(self.thumbWidth, 0, frameViewFrameWidth, CGRectGetHeight(self.frameView.frame))];
    CGFloat contentViewFrameWidth = CMTimeGetSeconds([self.asset duration]) <= self.maxLength + 0.5 ? self.bounds.size.width : frameViewFrameWidth + 2*self.thumbWidth;
    [self.contentView setFrame:CGRectMake(0, 0, contentViewFrameWidth, CGRectGetHeight(self.contentView.frame))];
    [self.scrollView setContentSize:self.contentView.frame.size];
    NSInteger minFramesNeeded = screenWidth / picWidth + 1;
    actualFramesNeeded =  factor * minFramesNeeded + 1;
    
    Float64 durationPerFrame = duration / (actualFramesNeeded*1.0);
    self.widthPerSecond = frameViewFrameWidth / duration;
    
    int preferredWidth = 0;
    NSMutableArray *times = [[NSMutableArray alloc] init];
    for (int i=1; i<actualFramesNeeded; i++){
        
        CMTime time = CMTimeMakeWithSeconds(i*durationPerFrame, 600);
        [times addObject:[NSValue valueWithCMTime:time]];
        
        UIImageView *tmp = [[UIImageView alloc] initWithImage:videoScreen];
        tmp.tag = i;
        
        CGRect currentFrame = tmp.frame;
        currentFrame.origin.x = i*picWidth;
        
        currentFrame.size.width = picWidth;
        preferredWidth += currentFrame.size.width;
        
        if( i == actualFramesNeeded-1){
            currentFrame.size.width-=6;
        }
        tmp.frame = currentFrame;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.frameView addSubview:tmp];
        });
        
        
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i=1; i<=[times count]; i++) {
            CMTime time = [((NSValue *)[times objectAtIndex:i-1]) CMTimeValue];
            
            CGImageRef halfWayImage = [self.imageGenerator copyCGImageAtTime:time actualTime:NULL error:NULL];
            
            UIImage *videoScreen;
            if ([self isRetina]){
                videoScreen = [[UIImage alloc] initWithCGImage:halfWayImage scale:2.0 orientation:UIImageOrientationUp];
            } else {
                videoScreen = [[UIImage alloc] initWithCGImage:halfWayImage];
            }
            
            CGImageRelease(halfWayImage);
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImageView *imageView = (UIImageView *)[self.frameView viewWithTag:i];
                [imageView setContentMode:UIViewContentModeScaleAspectFill];
                [imageView setImage:videoScreen];
            });
        }
    });
}

- (NSString *)timeFormatted:(int)totalSeconds
{
  int seconds = totalSeconds % 60;
  int minutes = (totalSeconds / 60) % 60;
  int hours = totalSeconds / 3600;

  NSString *finalString;

  if (hours > 0) {
      finalString = [NSString stringWithFormat:@"%02d:%02d:%02d",hours, minutes, seconds];
  }
  else{
      finalString = [NSString stringWithFormat:@"%02d:%02d", minutes, seconds];
  }

  return finalString;
}

- (BOOL)isRetina
{
    return ([[UIScreen mainScreen] respondsToSelector:@selector(displayLinkWithTarget:selector:)] &&
            ([UIScreen mainScreen].scale > 1.0));
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (CMTimeGetSeconds([self.asset duration]) <= self.maxLength + 0.5) {
        [UIView animateWithDuration:0.3 animations:^{
            [scrollView setContentOffset:CGPointZero];
        }];
    }
    [self notifyDelegateOfDidChange];
}

-(void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [self notifyDelegateOfEndEditing];
}


@end
