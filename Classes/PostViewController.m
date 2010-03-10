#import "PostViewController.h"
#import "BlogDataManager.h"
#import "WordPressAppDelegate.h"
#import "EditPostViewController.h"
#import "PostPreviewViewController.h"
#import "PostSettingsViewController.h"
#import "WPPhotosListViewController.h"
#import "WPNavigationLeftButtonView.h"
#import "PostsViewController.h"
#import "Reachability.h"
#import "CustomFieldsDetailController.h"
#import "CommentsViewController.h"
#import "WPPublishOnEditController.h"
#import "CInvisibleToolbar.h"

#define TAG_OFFSET 1010

@interface PostViewController (Private)

- (void)startTimer;
- (void)stopTimer;

- (void)saveAsDraft;
- (void)discard;
- (void)cancel;
- (void)conditionalLoadOfTabBarController;//to solve issue with crash when selecting comments tab from "new" (newPost) post editing view
- (void)savePostWithBlog:(NSMutableArray *)arrayPost;
- (void)removeProgressIndicator;

@end

@implementation PostViewController

@synthesize postDetailViewController, postDetailEditController, postPreviewController, postSettingsController, postsListController, hasChanges, mode, tabController, photosListController, saveButton;
@synthesize leftView, isVisible;
@synthesize customFieldsDetailController;
@synthesize commentsViewController;
@synthesize selectedViewController;

@synthesize toolbar;
@synthesize contentView;
@synthesize popoverController;

@synthesize commentsButton;
@synthesize photosButton;
@synthesize settingsButton;

@synthesize editToolbar;
@synthesize cancelEditButton;

@dynamic leftBarButtonItemForEditPost;
@dynamic rightBarButtonItemForEditPost;

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    [selectedViewController viewWillDisappear:NO];
    [viewController viewWillAppear:NO];
    
//    if (viewController == photosListController) {
//        if ((self.interfaceOrientation == UIInterfaceOrientationLandscapeLeft) || (self.interfaceOrientation == UIInterfaceOrientationLandscapeRight)) {
//            [photosListController.view addSubview:photoEditingStatusView];
//        } else if ((self.interfaceOrientation == UIInterfaceOrientationPortrait) || (self.interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)) {
//            [photoEditingStatusView removeFromSuperview];
//        }
//    }
//    else {
//        [photoEditingStatusView removeFromSuperview];
//    }

    if (hasChanges) {
        [leftView setTitle:@"Cancel"];
        self.leftBarButtonItemForEditPost = saveButton;
    }
    
    selectedViewController = viewController;
}

- (void)dealloc {
    [leftView release];
    [postDetailEditController release];
    [postPreviewController release];
    [postSettingsController release];
    [photosListController release];
    [commentsViewController release];
    [saveButton release];
	
	[toolbar release];
	[contentView release];
	[popoverController release];
	[photoPickerPopover release];
	[commentsButton release];
	[photosButton release];
	[settingsButton release];

    [self stopTimer];

    [super dealloc];
}

- (UIPopoverController *)popoverController;
{
	if (!popoverController) {
		UINavigationController *navController = [[[UINavigationController alloc] initWithRootViewController:nil] autorelease];
		navController.contentSizeForViewInPopover = CGSizeMake(320.0, 480.0);
		popoverController = [[UIPopoverController alloc] initWithContentViewController:navController];
	}
	return popoverController;
}

- (IBAction)cancelView:(id)sender {
	
	
    if (!hasChanges) {
        [self stopTimer];
		if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
			[self.navigationController popViewControllerAnimated:YES];
		} else {
			[self dismissModalViewControllerAnimated:YES];
		}
		NSLog(@"cancelView on PostViewController");
        return;
    }
	
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
		[postSettingsController endEditingAction:nil];
		[postDetailEditController endEditingAction:nil];
	}

    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@"You have unsaved changes."
                                  delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Discard"
                                  otherButtonTitles:nil];
    actionSheet.tag = 201;
    actionSheet.actionSheetStyle = UIActionSheetStyleAutomatic;
    [actionSheet showInView:self.view];
    WordPressAppDelegate *delegate = [[UIApplication sharedApplication] delegate];
    [delegate setAlertRunning:YES];

    [actionSheet release];
}

- (IBAction)saveAction:(id)sender {
    //saveButton.title = @"Save";
    NSLog(@"Inside Save Action");
    BlogDataManager *dm = [BlogDataManager sharedDataManager];

     if (![[dm.currentPost valueForKey:@"post_status"] isEqualToString:@"Local Draft"]) {
        if ([[Reachability sharedReachability] internetConnectionStatus] == NotReachable) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Communication Error."
                                  message:@"no internet connection."
                                  delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
            alert.tag = TAG_OFFSET;
            [alert show];

            WordPressAppDelegate *delegate = [[UIApplication sharedApplication] delegate];
            [delegate setAlertRunning:YES];
            [alert release];
            return;
        }
    }

    if (!hasChanges) {
        [self stopTimer];
        [self.navigationController popViewControllerAnimated:YES];
		NSLog(@"fdsa");
        return;
    }

	NSString *postStatus = [dm.currentPost valueForKey:@"post_status"];
	if( ![postStatus isEqual:@"Local Draft"] )
	{ 
		[self performSelectorInBackground:@selector(addProgressIndicator) withObject:nil];
    }
	
    //Code for scaling image based on post settings
	NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSArray *photosArray = [dm.currentPost valueForKey:@"Photos"];
    NSString *filepath;

    for (int i = 0; i <[photosArray count]; i++) {
        filepath = [photosArray objectAtIndex:i];
        NSString *imagePath = [NSString stringWithFormat:@"%@/%@", [dm blogDir:dm.currentBlog], filepath];
        UIImage *scaledImage = [photosListController scaleAndRotateImage:[UIImage imageWithContentsOfFile:imagePath] scaleFlag:YES];
        NSData *imageData = UIImageJPEGRepresentation(scaledImage, 0.5);
        [imageData writeToFile:imagePath atomically:YES];
		
		if(pool)
			[pool release];
		
		pool=[[NSAutoreleasePool alloc] init];

    }
	[pool release];

    //for handling more tag text.
    [(NSMutableDictionary *)[BlogDataManager sharedDataManager].currentPost setValue:@"" forKey:@"mt_text_more"];
    [postSettingsController endEditingAction:nil];
    [postDetailEditController endEditingAction:nil];

    NSString *description = [dm.currentPost valueForKey:@"description"];
    NSString *title = [dm.currentPost valueForKey:@"title"];
    NSArray *photos = [dm.currentPost valueForKey:@"Photos"];

    if ((!description ||[description isEqualToString:@""]) &&
        (!title ||[title isEqualToString:@""]) &&
        (!photos || ([photos count] == 0))) {
        NSString *msg = [NSString stringWithFormat:@"Please provide either a title or description or attach photos to the post before saving."];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Post Error"
                              message:msg
                              delegate:self
                              cancelButtonTitle:nil
                              otherButtonTitles:@"OK", nil];
        alert.tag = TAG_OFFSET;
        [alert show];

        WordPressAppDelegate *delegate = [[UIApplication sharedApplication] delegate];
        [delegate setAlertRunning:YES];

        [alert release];

        [self cancel];
        return;
    }

    if (![dm postDescriptionHasValidDescription:dm.currentPost]) {
        [self cancel];
        return;
    }

   // NSString *postStatus = [dm.currentPost valueForKey:@"post_status"];
	//[self.navigationController popViewControllerAnimated:YES];
	NSLog(@"just attempted to pop the viewController BEFORE the save");
    if ([postStatus isEqual:@"Local Draft"])
        [self saveAsDraft];else {
       // [self performSelectorInBackground:@selector(addProgressIndicator) withObject:nil];
        //Need to release params
        NSMutableArray *params = [[[NSMutableArray alloc] initWithObjects:dm.currentPost, dm.currentBlog, nil] autorelease];
        BOOL isCurrentPostDraft = dm.isLocaDraftsCurrent;

        if (isCurrentPostDraft)
            [dm saveCurrentPostAsDraftWithAsyncPostFlag];
			
		NSString *postId = [dm savePostsFileWithAsynPostFlag:[params objectAtIndex:0]];
		NSMutableArray *argsArray = [NSMutableArray arrayWithArray:params];
		int count = [argsArray count];
		[argsArray insertObject:postId atIndex:count];

		[self savePostWithBlog:argsArray];
		
		hasChanges = NO;
//		[dm removeAutoSavedCurrentPostFile];

		[self removeProgressIndicator];
		
		[self.navigationController popViewControllerAnimated:YES];
		
    }
}

- (void)autoSaveCurrentPost:(NSTimer *)aTimer {
    if (hasChanges) {
        [postDetailViewController updateValuesToCurrentPost];
        [postDetailEditController updateValuesToCurrentPost];
        [postSettingsController updateValuesToCurrentPost];

        BlogDataManager *dm = [BlogDataManager sharedDataManager];
        [dm autoSaveCurrentPost];
    }
}

- (void)startTimer {
    if (!autoSaveTimer) {
        autoSaveTimer = [[NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(autoSaveCurrentPost:) userInfo:nil repeats:YES] retain];
    }
}

- (void)stopTimer {
    if (autoSaveTimer) {
        [autoSaveTimer invalidate];
        [autoSaveTimer release];
        autoSaveTimer = nil;
    }
}

- (void)refreshUIForCompose {
	if (hasChanges == NO)
		[self setRightBarButtonItemForEditPost:nil];
	
    [tabController setSelectedViewController:[[tabController viewControllers] objectAtIndex:0]];
    UIViewController *vc = [[tabController viewControllers] objectAtIndex:0];
    self.title = vc.title;

	[postDetailViewController refreshUIForCompose];
    [postDetailEditController refreshUIForCompose];
    [postSettingsController reloadData];
    [photosListController refreshData];

    [self updatePhotosBadge];
}

- (void)refreshUIForCurrentPost {
    [self setRightBarButtonItemForEditPost:nil];

    [tabController setSelectedViewController:[[tabController viewControllers] objectAtIndex:0]];
    UIViewController *vc = [[tabController viewControllers] objectAtIndex:0];
    self.title = vc.title;
    [postDetailViewController refreshUIForCurrentPost];
    [postDetailEditController refreshUIForCurrentPost];
    [postSettingsController reloadData];
    [photosListController refreshData];

    [self updatePhotosBadge];
}

- (void)updatePhotosBadge {
    int photoCount = [[[BlogDataManager sharedDataManager].currentPost valueForKey:@"Photos"] count];
	
	if (tabController) {
		if (photoCount)
			photosListController.tabBarItem.badgeValue = [NSString stringWithFormat:@"%d", photoCount];
		else
			photosListController.tabBarItem.badgeValue = nil;
	} else if (toolbar) {
		if (!photoCount)
			photosButton.title = @"No Photos";
		else if (photoCount == 1)
			photosButton.title = @"1 Photo";
		else
			photosButton.title = [NSString stringWithFormat:@"%d Photos", photoCount];
	}
}

#pragma mark -
#pragma mark UIActionSheetDelegate methods

- (void)addProgressIndicator {
    NSAutoreleasePool *apool = [[NSAutoreleasePool alloc] init];
    UIActivityIndicatorView *aiv = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    UIBarButtonItem *activityButtonItem = [[UIBarButtonItem alloc] initWithCustomView:aiv];
    [aiv startAnimating];
    [aiv release];

    [self setRightBarButtonItemForEditPost:activityButtonItem];
    [activityButtonItem release];
    [apool release];
}

- (void)removeProgressIndicator {
    if (hasChanges) {
        if ([[leftView title] isEqualToString:@"Posts"] || [[self.leftBarButtonItemForEditPost title] isEqualToString:@"Done"])
            [leftView setTitle:@"Cancel"];

        self.leftBarButtonItemForEditPost = saveButton;
    } else {
        self.rightBarButtonItemForEditPost = nil;
    }
}

- (void)saveAsDraft {
    BlogDataManager *dm = [BlogDataManager sharedDataManager];
    [dm saveCurrentPostAsDraft];
    hasChanges = NO;
    self.rightBarButtonItemForEditPost = nil;
    [self stopTimer];
    [dm removeAutoSavedCurrentPostFile];
    [self discard];
}

- (void)discard {
    hasChanges = NO;
    self.rightBarButtonItemForEditPost = nil;
    [self stopTimer];
    [[BlogDataManager sharedDataManager] clearAutoSavedContext];
	
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
		[self.navigationController popViewControllerAnimated:YES];
	} else {
		[self dismissModalViewControllerAnimated:YES];
	}
	
}

- (void)cancel {
    hasChanges = YES;

    if ([[leftView title] isEqualToString:@"Posts"])
        [leftView setTitle:@"Cancel"];
}

- (void)savePostWithBlog:(NSMutableArray *)arrayPost {
    BlogDataManager *dm = [BlogDataManager sharedDataManager];
    NSString *postId = [arrayPost lastObject];
    BOOL isCurrentPostDraft = dm.isLocaDraftsCurrent;

    BOOL savePostStatus = [dm savePost:[arrayPost objectAtIndex:0]];
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    [self stopTimer];

    if (savePostStatus) {
		[dm removeAutoSavedCurrentPostFile];
        [dict setValue:postId forKey:@"savedPostId"];
        [dict setValue:[[dm currentPost] valueForKey:@"postid"] forKey:@"originalPostId"];
        [dict setValue:[NSNumber numberWithInt:isCurrentPostDraft] forKey:@"isCurrentPostDraft"];
    
	} else {
        [dm removeTempFileForUnSavedPost:postId];

        if (isCurrentPostDraft) {
            [dm restoreUnsavedDraft];
        }
    }

    hasChanges = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AsynchronousPostIsPosted" object:nil userInfo:dict];
    [dict release];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([actionSheet tag] == 201) {
        if (buttonIndex == 0) {
            [self discard];
        }

        if (buttonIndex == 1) {
            [self cancel];
        }
    }

    WordPressAppDelegate *delegate = [[UIApplication sharedApplication] delegate];
    [delegate setAlertRunning:NO];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag != TAG_OFFSET) {
        [self discard];
    }

    WordPressAppDelegate *delegate = [[UIApplication sharedApplication] delegate];
    [delegate setAlertRunning:NO];
}

- (void)setHasChanges:(BOOL)aFlag {
    //NSLog(@"inside PostViewController:setHasChanges");

    if (hasChanges == NO && aFlag == YES)
        [self startTimer];

    hasChanges = aFlag;

    if (hasChanges) {
        if ([[leftView title] isEqualToString:@"Posts"])
            [leftView setTitle:@"Cancel"];

        self.rightBarButtonItemForEditPost = saveButton;
    }

    NSNumber *postEdited = [NSNumber numberWithBool:hasChanges];
    [[[BlogDataManager sharedDataManager] currentPost] setObject:postEdited forKey:@"hasChanges"];
}

#pragma mark -
#pragma mark View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    if (!saveButton) {
        saveButton = [[UIBarButtonItem alloc] init];
        saveButton.title = @"Save";
        saveButton.target = self;
        saveButton.style = UIBarButtonItemStyleDone;
        saveButton.action = @selector(saveAction :);
    }
	
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone)
	{
			//conditionalLoadOfTabBarController is now referenced from viewWillAppear.  Solves Ticket #223 (crash when selecting comments from new post view)
	    if (!leftView) {
			leftView = [WPNavigationLeftButtonView createCopyOfView];
			[leftView setTitle:@"Posts"];
		}
	}
}
//shouldAutorotateToInterfaceOrientation


- (void)viewWillAppear:(BOOL)animated {
	NSLog(@"inside PostViewController:viewWillAppear");
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
		if ((self.interfaceOrientation == UIInterfaceOrientationPortrait) || (self.interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)) {
			[postDetailEditController setTextViewHeight:202];
		}
		
		if ((self.interfaceOrientation == UIInterfaceOrientationLandscapeLeft) || (self.interfaceOrientation == UIInterfaceOrientationLandscapeRight)) {
			if (postDetailEditController.isEditing == NO) {
				//[postDetailEditController setTextViewHeight:57]; //#148
			} else {
				[postDetailEditController setTextViewHeight:116];
			}
		}
	}

    [leftView setTarget:self withAction:@selector(cancelView:)];
	
	if (![[[[BlogDataManager sharedDataManager] currentPost] valueForKey:@"title"] isEqualToString:@""]) {
		self.navigationItem.title = [[[BlogDataManager sharedDataManager] currentPost] valueForKey:@"title"];
	}else{
		self.navigationItem.title = @"Write";
	}

    if (hasChanges == YES) {
        if ([[leftView title] isEqualToString:@"Posts"]) {
            [leftView setTitle:@"Cancel"];
        }
        
        self.rightBarButtonItemForEditPost = saveButton;
    } else {
        [leftView setTitle:@"Posts"];
        self.rightBarButtonItemForEditPost = nil;
    }
	
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
		UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithCustomView:leftView];
		self.leftBarButtonItemForEditPost = cancelButton;
		[cancelButton release];
	}

    [super viewWillAppear:animated];
	[self conditionalLoadOfTabBarController];

    if (mode == editPost) {
        [self refreshUIForCurrentPost];
    } else if (mode == newPost) {
        [self refreshUIForCompose];
    } else if (mode == autorecoverPost) {
        [self refreshUIForCurrentPost];
        self.hasChanges = YES;
    }

    if (mode != newPost)
		mode = refreshPost;
    [commentsViewController setIndexForCurrentPost:[[BlogDataManager sharedDataManager] currentPostIndex]];
    [[tabController selectedViewController] viewWillAppear:animated];
	
	isVisible = YES;
}

- (void)conditionalLoadOfTabBarController {
	// Icons designed by, and included with permission of, IconBuffet | iconbuffet.com
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:5];
	
	// post detail controllers
    if (postDetailEditController == nil) {
        postDetailEditController = [[EditPostViewController alloc] initWithNibName:@"EditPostViewController" bundle:nil];
    }
	
    postDetailEditController.title = @"Write";
    postDetailEditController.tabBarItem.image = [UIImage imageNamed:@"write.png"];
    postDetailEditController.postDetailViewController = self;
    [array addObject:postDetailEditController];
	
	// the iPad has two of em...
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		postDetailViewController = [[EditPostViewController alloc] initWithNibName:@"EditPostViewController" bundle:nil];
		[postDetailViewController disableInteraction];
	}
    
    //if (mode == 1 || mode == 2 || mode == 3) { //don't load this tab if mode == 0 (new post) since comments are irrelevant to a brand new post
	NSString *postStatus = [[BlogDataManager sharedDataManager].currentPost valueForKey:@"post_status"];
	if (mode != newPost && ![postStatus isEqualToString:@"Local Draft"]) { //don't load commentsViewController tab if it's a new post or a local draft since comments are irrelevant to a brand new post
		if (commentsViewController == nil) {
			commentsViewController = [[CommentsViewController alloc] initWithNibName:@"CommentsViewController" bundle:nil];
		}
		
		commentsViewController.title = @"Comments";
		commentsViewController.tabBarItem.image = [UIImage imageNamed:@"talk_bubbles.png"];
		[array addObject:commentsViewController];
	}
	
    if (photosListController == nil) {
        photosListController = [[WPPhotosListViewController alloc] initWithNibName:@"WPPhotosListViewController" bundle:nil];
    }
	
    photosListController.title = @"Photos";
    photosListController.tabBarItem.image = [UIImage imageNamed:@"photos.png"];
    photosListController.delegate = self;
	
    [array addObject:photosListController];
	
    if (postPreviewController == nil) {
        postPreviewController = [[PostPreviewViewController alloc] initWithNibName:@"PostPreviewViewController" bundle:nil];
    }
	
    postPreviewController.title = @"Preview";
    postPreviewController.tabBarItem.image = [UIImage imageNamed:@"preview.png"];
    postPreviewController.postDetailViewController = self;
    [array addObject:postPreviewController];
	
    if (postSettingsController == nil) {
        postSettingsController = [[PostSettingsViewController alloc] initWithNibName:@"PostSettingsViewController" bundle:nil];
    }
	
    postSettingsController.title = @"Settings";
    postSettingsController.tabBarItem.image = [UIImage imageNamed:@"settings.png"];
    postSettingsController.postDetailViewController = self;
    [array addObject:postSettingsController];
	
	if (tabController) {
		tabController.viewControllers = array;
		self.view = tabController.view;
	}
	else {
		postDetailViewController.view.frame = contentView.bounds;
		[contentView addSubview:postDetailViewController.view];
	}
	
    [array release];
}

- (void)viewWillDisappear:(BOOL)animated {
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
		if ((self.interfaceOrientation == UIInterfaceOrientationLandscapeLeft) || (self.interfaceOrientation == UIInterfaceOrientationLandscapeRight)) {
			[postDetailEditController setTextViewHeight:202];
		}
	}

//    [photoEditingStatusView removeFromSuperview];

    if (postDetailEditController.currentEditingTextField)
        [postDetailEditController.currentEditingTextField resignFirstResponder];

    [super viewWillDisappear:animated];
   if (mode != newPost)
	   mode = refreshPost;
    [postPreviewController stopLoading];
	isVisible = NO;
}

- (void)didReceiveMemoryWarning {
    WPLog(@"%@ %@", self, NSStringFromSelector(_cmd));
    [super didReceiveMemoryWarning];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	// iPad apps should always autorotate
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		return YES;
	}
	
	NSLog(@"inside PostViewController: should autorotate");
//    if ([[[[self tabController] selectedViewController] title] isEqualToString:@"Photos"]) {
//        if ((interfaceOrientation == UIInterfaceOrientationLandscapeLeft) || (interfaceOrientation == UIInterfaceOrientationLandscapeRight)) {
//            [photosListController.view addSubview:photoEditingStatusView];
//        } else if ((interfaceOrientation == UIInterfaceOrientationPortrait) || (interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)) {
//            [photoEditingStatusView removeFromSuperview];
//        }
//    }
	

    //Code to disable landscape when alert is raised.
    WordPressAppDelegate *delegate = [[UIApplication sharedApplication] delegate];

    if ([delegate isAlertRunning] == YES) {
        return NO;
    }

    if ((interfaceOrientation == UIInterfaceOrientationPortrait) || (interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)) {
        [postDetailEditController setTextViewHeight:202];
		return YES;
    }

    if ((interfaceOrientation == UIInterfaceOrientationLandscapeLeft) || (interfaceOrientation == UIInterfaceOrientationLandscapeRight)) {
        if (self.interfaceOrientation != interfaceOrientation) {
            if (postDetailEditController.isEditing == NO) {
              //  [postDetailEditController setTextViewHeight:57]; //#148
            } else {
                [postDetailEditController setTextViewHeight:116];
				return YES;
            }
        }
    }
	if ([tabController.selectedViewController.title isEqualToString:@"Settings"]) {
		NSLog(@"PostViewController:should autorotate, isEqualToString Settings");
		return NO;
		
    }
	

    //return YES;
	return NO; //trac ticket #148
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
	//[self.selectedViewController didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    if ([tabController.selectedViewController.title isEqualToString:@"Settings"]) {
        [postSettingsController.tableView reloadData];
    }
}

- (void)useImage:(UIImage *)theImage {
    BlogDataManager *dataManager = [BlogDataManager sharedDataManager];
    self.hasChanges = YES;

    id currentPost = dataManager.currentPost;

    if (![currentPost valueForKey:@"Photos"]) {
        [currentPost setValue:[NSMutableArray array] forKey:@"Photos"];
    }

    UIImage *image = [photosListController scaleAndRotateImage:theImage scaleFlag:NO];
    [[currentPost valueForKey:@"Photos"] addObject:[dataManager saveImage:image]];

    [self updatePhotosBadge];
}

- (id)photosDataSource {
    return [[[BlogDataManager sharedDataManager] currentPost] valueForKey:@"Photos"];
}

#pragma mark -
#pragma mark iPad actions

- (UINavigationItem *)navigationItemForEditPost;
{
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
		return self.navigationItem;
	} else if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		return postDetailEditController.navigationItem;
	}
	return nil;
}

- (UIBarButtonItem *)leftBarButtonItemForEditPost;
{
	return [self navigationItemForEditPost].leftBarButtonItem;
}

- (void)setLeftBarButtonItemForEditPost:(UIBarButtonItem *)item;
{
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
		self.navigationItem.leftBarButtonItem = item;
	} else if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		postDetailEditController.navigationItem.leftBarButtonItem = item;
	}
}

- (UIBarButtonItem *)rightBarButtonItemForEditPost;
{
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
		return self.navigationItem.rightBarButtonItem;
	} else if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		return [editToolbar.items lastObject];
	}
	return nil;
}

- (void)setRightBarButtonItemForEditPost:(UIBarButtonItem *)item;
{
	if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
		self.navigationItem.rightBarButtonItem = item;
	} else if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		NSArray *currentItems = editToolbar.items;
		// TODO: magic numbers
		NSMutableArray *newItems = [NSMutableArray arrayWithArray:[currentItems subarrayWithRange:NSMakeRange(0, 4)]];
		if (item)
			[newItems addObject:item];
		[editToolbar setItems:newItems animated:YES];
		CGRect frame = editToolbar.frame;
		if (newItems.count > 4) {
			frame.size.width = 240.0;
		} else {
			frame.size.width = 185.0;
		}
		editToolbar.frame = frame;
	}
}

- (IBAction)editAction:(id)sender;
{
	UINavigationController *navController = [[[UINavigationController alloc] initWithRootViewController:postDetailEditController] autorelease];
	navController.modalPresentationStyle = UIModalPresentationPageSheet;
	navController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
	if (!editToolbarItem) {
		editToolbarItem = [[UIBarButtonItem alloc] initWithCustomView:editToolbar];
	}
	postDetailEditController.navigationItem.rightBarButtonItem = editToolbarItem;
	postDetailEditController.navigationItem.leftBarButtonItem = cancelEditButton;
	[self.splitViewController presentModalViewController:navController animated:YES];
}

- (IBAction)commentsAction:(id)sender;
{
	[(UINavigationController *)(self.popoverController.contentViewController) setViewControllers:[NSArray arrayWithObject:commentsViewController] animated:NO];
	commentsViewController.contentSizeForViewInPopover = popoverController.contentViewController.contentSizeForViewInPopover;
	[popoverController presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (IBAction)picturesAction:(id)sender;
{
	[(UINavigationController *)(self.popoverController.contentViewController) setViewControllers:[NSArray arrayWithObject:photosListController] animated:NO];
	photosListController.contentSizeForViewInPopover = popoverController.contentViewController.contentSizeForViewInPopover;
	[popoverController presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (IBAction)settingsAction:(id)sender;
{
	[(UINavigationController *)(self.popoverController.contentViewController) setViewControllers:[NSArray arrayWithObject:postSettingsController] animated:NO];
	postSettingsController.contentSizeForViewInPopover = popoverController.contentViewController.contentSizeForViewInPopover;
	[popoverController presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (IBAction)addPhotoAction:(id)sender;
{
	if ([WPImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        WPImagePickerController *picker = [[[UIImagePickerController alloc] init] autorelease];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
		self.popoverController.contentViewController = picker;
	}
}

- (IBAction)previewAction:(id)sender;
{
//	[UIView beginAnimations:nil context:nil];
	UINavigationController *modal = (UINavigationController *)self.modalViewController;
	postPreviewController.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithCustomView:previewToolbar] autorelease];
	[modal setViewControllers:[NSArray arrayWithObject:postPreviewController]];
//	[UIView commitAnimations];
}

- (IBAction)previewEditAction:(id)sender;
{
//	[UIView beginAnimations:nil context:nil];
	UINavigationController *modal = (UINavigationController *)self.modalViewController;
	[modal setViewControllers:[NSArray arrayWithObject:postDetailEditController]];
//	[UIView commitAnimations];
}

- (IBAction)previewPublishAction:(id)sender;
{
}

#pragma mark -
#pragma mark Photo list delegate: iPad

- (void)displayPhotoListImagePicker:(UIImagePickerController *)picker;
{
	if (!photoPickerPopover) {
		photoPickerPopover = [[UIPopoverController alloc] initWithContentViewController:picker];
	}
	picker.contentSizeForViewInPopover = popoverController.contentViewController.contentSizeForViewInPopover;
	photoPickerPopover.contentViewController = picker;
	[popoverController dismissPopoverAnimated:NO];
	[photoPickerPopover presentPopoverFromBarButtonItem:photosButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:NO];
}

- (void)hidePhotoListImagePicker;
{
	[photoPickerPopover dismissPopoverAnimated:NO];
	[popoverController presentPopoverFromBarButtonItem:photosButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:NO];
}

@end
