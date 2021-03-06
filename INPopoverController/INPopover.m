//
//  INPopover.m
//  Copyright 2011-2014 Indragie Karunaratne. All rights reserved.
//

#import "INPopover.h"
#import "INPopoverDelegate.h"
#import "INPopoverWindow.h"
#import "INPopoverWindowFrame.h"
#import "INPopoverParentWindow.h"
#include <QuartzCore/QuartzCore.h>

@implementation INPopover 

@synthesize delegate = _delegate;
@synthesize color = _color;
@synthesize borderColor = _borderColor;
@synthesize topHighlightColor = _topHighlightColor;
@synthesize borderWidth = _borderWidth;
@synthesize cornerRadius = _cornerRadius;
@synthesize arrowSize = _arrowSize;
@synthesize edge = _edge;
@synthesize contentSize = _contentSize;
@synthesize closesWhenEscapeKeyPressed = _closesWhenEscapeKeyPressed;
@synthesize closesWhenPopoverResignsKey = _closesWhenPopoverResignsKey;
@synthesize closesWhenApplicationBecomesInactive = _closesWhenApplicationBecomesInactive;
@synthesize animates = _animates;
@synthesize animationType =  _animationType;
@synthesize contentViewController =  _contentViewController;
@synthesize positionView = _positionView;
@synthesize popoverWindow = _popoverWindow;
@synthesize popoverIsVisible = _popoverIsVisible;

#pragma mark -
#pragma mark Initialization

- (id)init
{
	if ((self = [super init])) {
		[self _setInitialPropertyValues];
	}
	return self;
}

- (void)awakeFromNib
{
	[super awakeFromNib];
	[self _setInitialPropertyValues];
}

#pragma mark - 
#pragma mark - Memory Management

- (void)dealloc
{
  [_color release];
  [_borderColor release];
  [_topHighlightColor release];
	[_popoverWindow.popover release];
  [super dealloc];
}

#pragma mark -
#pragma mark Public Methods

- (id)initWithContentViewController:(NSViewController *)viewController
{
	if ((self = [super init])) {
		[self _setInitialPropertyValues];
		self.contentViewController = viewController;
	}
	return self;
}

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)positionView preferredEdge:(NSRectEdge)edge
{
	if (self.popoverIsVisible) {return;} // If it's already visible, do nothing
	NSWindow *mainWindow = [positionView window];
	_positionView = positionView;
	_viewRect = rect;
	_screenRect = [positionView convertRect:rect toView:nil]; // Convert the rect to window coordinates
	_screenRect.origin = [mainWindow convertBaseToScreen:_screenRect.origin]; // Convert window coordinates to screen coordinates
	NSRectEdge calculatedEdge = [self _edgeWithPreferredEdge:edge]; // Calculate the best arrow direction
	[self _setEdge:calculatedEdge]; // Change the arrow direction of the popover
	NSRect windowFrame = [self popoverFrameWithSize:self.contentSize andEdge:calculatedEdge]; // Calculate the window frame based on the arrow direction
	[_popoverWindow setFrame:windowFrame display:YES]; // Se the frame of the window
	[(CAAnimation *)[_popoverWindow animationForKey:@"alphaValue"] setDelegate:self];

	// Show the popover
	[self _callDelegateMethod:@selector(popoverWillShow:)]; // Call the delegate
	if (self.animates && self.animationType != INPopoverAnimationTypeFadeOut) {
		// Animate the popover in
		[_popoverWindow presentAnimated];
	} else {
		[_popoverWindow setAlphaValue:1.0];
		[mainWindow addChildWindow:_popoverWindow ordered:NSWindowAbove]; // Add the popover as a child window of the main window
		[_popoverWindow makeKeyAndOrderFront:nil]; // Show the popover
		[self _callDelegateMethod:@selector(popoverDidShow:)]; // Call the delegate
	}

	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

  [nc addObserver:self selector:@selector(_positionViewFrameChanged:) name:NSViewFrameDidChangeNotification object:self.positionView];

	// When -closesWhenPopoverResignsKey is set to YES, the popover will automatically close when the popover loses its key status
	if (self.closesWhenPopoverResignsKey) {
		[nc addObserver:self selector:@selector(performClose:) name:NSWindowDidResignKeyNotification object:_popoverWindow];
		if (!self.closesWhenApplicationBecomesInactive) {
			[nc addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];
		}
	} else if (self.closesWhenApplicationBecomesInactive) {
		// this is only needed if closesWhenPopoverResignsKey is NO, otherwise we already get a "resign key" notification when resigning active
		[nc addObserver:self selector:@selector(performClose:) name:NSApplicationDidResignActiveNotification object:nil];
	}
}

- (void)recalculateAndResetEdge
{
	NSRectEdge edge = [self _edgeWithPreferredEdge:self.edge];
	[self _setEdge:edge];
}

- (IBAction)performClose:(id)sender
{
	if (![_popoverWindow isVisible]) {return;}
	if ([sender isKindOfClass:[NSNotification class]] && [[(NSNotification *) sender name] isEqualToString:NSWindowDidResignKeyNotification]) {
		// ignore "resign key" notification sent when app becomes inactive unless closesWhenApplicationBecomesInactive is enabled
		if (!self.closesWhenApplicationBecomesInactive && ![NSApp isActive])
			return;
	}
	BOOL close = YES;
	// Check to see if the delegate has implemented the -popoverShouldClose: method
	if ([self.delegate respondsToSelector:@selector(popoverShouldClose:)]) {
		close = [self.delegate popoverShouldClose:self];
	}
	if (close) {[self close];}
}

- (void)close
{
	if (![_popoverWindow isVisible]) {return;}
	[self _callDelegateMethod:@selector(popoverWillClose:)]; // Call delegate
	if (self.animates && self.animationType != INPopoverAnimationTypeFadeIn) {
		[_popoverWindow dismissAnimated];
	} else {
		[self _closePopoverAndResetVariables];
	}
}

// Calculate the frame of the window depending on the arrow direction
- (NSRect)popoverFrameWithSize:(NSSize)contentSize andEdge:(NSRectEdge)edge
{
	NSRect contentRect = NSZeroRect;
	contentRect.size = contentSize;
	NSRect windowFrame = [_popoverWindow frameRectForContentRect:contentRect];
	if (edge == NSRectEdgeMaxX) {
		CGFloat xOrigin = NSMidX(_screenRect) - floor(windowFrame.size.width / 2.0);
		CGFloat yOrigin = NSMinY(_screenRect) - windowFrame.size.height;
		windowFrame.origin = NSMakePoint(xOrigin, yOrigin);
	} else if (edge == NSRectEdgeMinY) {
		CGFloat xOrigin = NSMidX(_screenRect) - floor(windowFrame.size.width / 2.0);
		windowFrame.origin = NSMakePoint(xOrigin, NSMaxY(_screenRect));
	} else if (edge == NSRectEdgeMinX) {
		CGFloat yOrigin = NSMidY(_screenRect) - floor(windowFrame.size.height / 2.0);
		windowFrame.origin = NSMakePoint(NSMaxX(_screenRect), yOrigin);
	} else if (edge == NSRectEdgeMaxY) {
		CGFloat xOrigin = NSMinX(_screenRect) - windowFrame.size.width;
		CGFloat yOrigin = NSMidY(_screenRect) - floor(windowFrame.size.height / 2.0);
		windowFrame.origin = NSMakePoint(xOrigin, yOrigin);
	} else {
		// If no arrow direction is specified, just return an empty rect
		windowFrame = NSZeroRect;
	}
	return windowFrame;
}

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)flag
{
#pragma unused(animation)
#pragma unused(flag)
	// Detect the end of fade out and close the window
	if (0.0 == [_popoverWindow alphaValue])
		[self _closePopoverAndResetVariables];
	else if (1.0 == [_popoverWindow alphaValue]) {
		[[_positionView window] addChildWindow:_popoverWindow ordered:NSWindowAbove];
		[self _callDelegateMethod:@selector(popoverDidShow:)];
	}
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
	// when the user clicks in the parent window for activating the app, the parent window becomes key which prevents 
	if ([_popoverWindow isVisible])
		[self performSelector:@selector(checkPopoverKeyWindowStatus) withObject:nil afterDelay:0];
}

- (void)checkPopoverKeyWindowStatus
{
	id parentWindow = [_positionView window]; // could be INPopoverParentWindow
	BOOL isKey = [parentWindow respondsToSelector:@selector(isReallyKeyWindow)] ? [parentWindow isReallyKeyWindow] : [parentWindow isKeyWindow];
	if (isKey)
		[_popoverWindow makeKeyWindow];
}

- (void) setBehavior: (NSInteger) behavior
  {
  }

#pragma mark -
#pragma mark Getters

- (NSColor *)color
{
	return _popoverWindow.frameView.color;
}

- (CGFloat)borderWidth
{
	return _popoverWindow.frameView.borderWidth;
}

- (NSColor *)borderColor
{
	return _popoverWindow.frameView.borderColor;
}

- (NSColor *)topHighlightColor
{
	return _popoverWindow.frameView.topHighlightColor;
}

- (CGFloat)cornerRadius
{
	return _popoverWindow.frameView.cornerRadius;
}

- (NSSize)arrowSize
{
	return _popoverWindow.frameView.arrowSize;
}

- (NSRectEdge)edge
{
	return _popoverWindow.frameView.edge;
}

- (NSView *)contentView
{
	return [_popoverWindow popoverContentView];
}

- (BOOL)popoverIsVisible
{
	return [_popoverWindow isVisible];
}

#pragma mark -
#pragma mark Setters

- (void)setColor:(NSColor *)newColor
{
	_popoverWindow.frameView.color = newColor;
}

- (void)setBorderWidth:(CGFloat)newBorderWidth
{
	_popoverWindow.frameView.borderWidth = newBorderWidth;
}

- (void)setBorderColor:(NSColor *)newBorderColor
{
	_popoverWindow.frameView.borderColor = newBorderColor;
}

- (void)setTopHighlightColor:(NSColor *)newTopHighlightColor
{
	_popoverWindow.frameView.topHighlightColor = newTopHighlightColor;
}

- (void)setCornerRadius:(CGFloat)cornerRadius
{
	_popoverWindow.frameView.cornerRadius = cornerRadius;
}

- (void)setArrowSize:(NSSize)arrowSize
{
	_popoverWindow.frameView.arrowSize = arrowSize;
}

- (void)setContentViewController:(NSViewController *)newContentViewController
{
	if (_contentViewController != newContentViewController) {
		[_popoverWindow setPopoverContentView:nil]; // Clear the content view
		_contentViewController = newContentViewController;
		NSView *contentView = [_contentViewController view];
		self.contentSize = [contentView frame].size;
		[_popoverWindow setPopoverContentView:contentView];
	}
}

- (void)setContentSize:(NSSize)newContentSize
{
	// We use -frameRectForContentRect: just to get the frame size because the origin it returns is not the one we want to use. Instead, -windowFrameWithSize:andEdge: is used to  complete the frame
	_contentSize = newContentSize;
	NSRect adjustedRect = [self popoverFrameWithSize:newContentSize andEdge:self.edge];
	[_popoverWindow setFrame:adjustedRect display:YES animate:self.animates];
}

- (void)_setEdge:(NSRectEdge)edge
{
	_popoverWindow.frameView.edge = edge;
}

#pragma mark -
#pragma mark Private

// Set the default values for all the properties as described in the header documentation
- (void)_setInitialPropertyValues
{
	// Create an empty popover window
	_popoverWindow = [[INPopoverWindow alloc] initWithContentRect:NSZeroRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	_popoverWindow.popover = self;

	// set defaults like iCal popover
	self.color = [[NSColor colorWithCalibratedWhite:0.94 alpha:0.92] retain];
	self.borderColor = [[NSColor colorWithCalibratedWhite:1.0 alpha:0.92] retain];
	self.borderWidth = 1.0;
	self.closesWhenEscapeKeyPressed = YES;
	self.closesWhenPopoverResignsKey = YES;
	self.closesWhenApplicationBecomesInactive = NO;
	self.animates = YES;
	self.animationType = INPopoverAnimationTypePop;

	// create animation to get callback - delegate is set when opening popover to avoid memory cycles
	CAAnimation *animation = [CABasicAnimation animation];
	[_popoverWindow setAnimations:[NSDictionary dictionaryWithObject:animation forKey:@"alphaValue"]];
}

// Figure out which direction best stays in screen bounds
- (NSRectEdge)_edgeWithPreferredEdge:(NSRectEdge)edge
{
	NSRect screenFrame = [[[_positionView window] screen] frame];
	// If the window with the preferred arrow direction already falls within the screen bounds then no need to go any further
	NSRect windowFrame = [self popoverFrameWithSize:self.contentSize andEdge:edge];
	if (NSContainsRect(screenFrame, windowFrame)) {
		return edge;
	}
	// First thing to try is making the popover go opposite of its current direction
	NSRectEdge newEdge = NSRectEdgeMaxX;
	switch (edge) {
		case NSRectEdgeMaxY:
			newEdge = NSRectEdgeMinY;
			break;
		case NSRectEdgeMinY:
			newEdge = NSRectEdgeMaxY;
			break;
		case NSRectEdgeMinX:
			newEdge = NSRectEdgeMaxX;
			break;
		case NSRectEdgeMaxX:
			newEdge = NSRectEdgeMinX;
			break;
		default:
			break;
	}
	// If the popover now fits within bounds, then return the newly adjusted direction
	windowFrame = [self popoverFrameWithSize:self.contentSize andEdge:newEdge];
	if (NSContainsRect(screenFrame, windowFrame)) {
		return newEdge;
	}
	// Calculate the remaining space on each side and figure out which would be the best to try next
	CGFloat left = NSMinX(_screenRect);
	CGFloat right = screenFrame.size.width - NSMaxX(_screenRect);
	CGFloat up = screenFrame.size.height - NSMaxY(_screenRect);
	CGFloat down = NSMinY(_screenRect);
	BOOL arrowLeft = (right > left);
	BOOL arrowUp = (down > up);
	// Now the next thing to try is the direction with the most space
	switch (edge) {
		case NSRectEdgeMinY:
		case NSRectEdgeMaxY:
			newEdge = arrowLeft ? NSRectEdgeMinX : NSRectEdgeMaxX;
      break;
		case NSRectEdgeMinX:
		case NSRectEdgeMaxX:
			newEdge = arrowUp ? NSRectEdgeMaxY : NSRectEdgeMinY;
			break;
		default:
			break;
	}
	// If the popover now fits within bounds, then return the newly adjusted direction
	windowFrame = [self popoverFrameWithSize:self.contentSize andEdge:newEdge];
	if (NSContainsRect(screenFrame, windowFrame)) {
		return newEdge;
	}
	// If that didn't fit, then that means that it will be out of bounds on every side so just return the original direction
	return edge;
}

- (void)_positionViewFrameChanged:(NSNotification *)notification
{
	NSRect superviewBounds = [[self.positionView superview] bounds];
	if (!(NSContainsRect(superviewBounds, [self.positionView frame]))) {
		[self close]; // If the position view goes off screen then close the popover
		return;
	}
	NSRect newFrame = [_popoverWindow frame];
	_screenRect = [self.positionView convertRect:_viewRect toView:nil]; // Convert the rect to window coordinates
	_screenRect.origin = [[self.positionView window] convertBaseToScreen:_screenRect.origin]; // Convert window coordinates to screen coordinates
	NSRect calculatedFrame = [self popoverFrameWithSize:self.contentSize andEdge:self.edge]; // Calculate the window frame based on the arrow direction
	newFrame.origin = calculatedFrame.origin;
	[_popoverWindow setFrame:newFrame display:YES animate:NO]; // Set the frame of the window
}

- (void)_closePopoverAndResetVariables
{
	NSWindow *positionWindow = [self.positionView window];
	[_popoverWindow orderOut:nil]; // Close the window 
	[self _callDelegateMethod:@selector(popoverDidClose:)]; // Call the delegate to inform that the popover has closed
	[positionWindow removeChildWindow:_popoverWindow]; // Remove it as a child window
	[positionWindow makeKeyAndOrderFront:nil];
	// Clear all the ivars
	[self _setEdge:NSRectEdgeMinX];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	_positionView = nil;
	_screenRect = NSZeroRect;
	_viewRect = NSZeroRect;

	// When using ARC and no animation, there is a "message sent to deallocated instance" crash if setDelegate: is not performed at the end of the event.
	[[_popoverWindow animationForKey:@"alphaValue"] performSelector:@selector(setDelegate:) withObject:nil afterDelay:0];
}

- (void)_callDelegateMethod:(SEL)selector
{
	if ([self.delegate respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[self.delegate performSelector:selector withObject:self];
#pragma clang diagnostic pop
	}
}

@end
