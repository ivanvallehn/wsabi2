//
//  WSDeviceSetupController.h
//  wsabi2
//
//  Created by Matt Aronoff on 2/15/12.
 
//

#import <UIKit/UIKit.h>
#import "NBCLDeviceLink.h"
#import "constants.h"
#import "WSModalityMap.h"
#import "WSBDResult.h"
#import "WSBDParameter.h"
#import "WSCDDeviceDefinition.h"
#import "WSCDItem.h"
#import "ELCTextfieldCellWide.h"
#import "WSModalityChooserController.h"
#import "WSSubmodalityChooserController.h"

typedef enum {
	kStatusBlank = 0,
    kStatusChecking,
    kStatusNotFound,
    kStatusBadModality,
    kStatusBadSubmodality,
    kStatusSuccessful,
    kStatus_COUNT
} WSSensorSetupStatusType;


@interface WSDeviceSetupController : UIViewController <UITableViewDataSource, UITableViewDelegate,
                                                        UITextFieldDelegate, NBCLDeviceLinkDelegate>
{
    BOOL checkingSensor;
    
    NSTimer *sensorCheckTimer;
    
    //This will be a standalone single link, and won't be connected to 
    //the device link manager, because we don't want to stomp on existing
    //communications, and we only need rapid access to one endpoint (/info).
    NBCLDeviceLink *currentLink; 
}

-(IBAction)doneButtonPressed:(id)sender;
-(IBAction)cycleButtonPressed:(id)sender;
-(IBAction)checkAgainButtonPressed:(id)sender;
-(IBAction)editAddressButtonPressed:(id)sender;
-(IBAction)changeCaptureTypeButtonPressed:(id)sender;
-(IBAction)tappedBehindView:(id)sender;

-(void) dismissKeyboard:(UITapGestureRecognizer*)recog;

//Sensor interaction stuff
-(void) checkSensor:(NSTimer*)timer;

@property (nonatomic, strong) WSCDItem *item;
@property (nonatomic, strong) WSCDDeviceDefinition *deviceDefinition;
@property (nonatomic) WSSensorCaptureType submodality;
@property (nonatomic) WSSensorModalityType modality;

//Status stuff
@property (nonatomic) WSSensorSetupStatusType sensorCheckStatus;

@property (nonatomic, strong) IBOutlet UIView *statusContainer;
@property (nonatomic, strong) IBOutlet UIImageView *statusContainerBackgroundView;
@property (nonatomic, strong) IBOutlet UIButton *statusTextButton;

@property (nonatomic, strong) IBOutlet UIView *notFoundContainer;
@property (nonatomic, strong) IBOutlet UIButton *reconnectButton;

@property (nonatomic, strong) IBOutlet UIView *warningContainer;
@property (nonatomic, strong) IBOutlet UIButton *editAddressButton;
@property (nonatomic, strong) IBOutlet UIButton *changeCaptureTypeButton;

@property (nonatomic, strong) IBOutlet UIView *checkingContainer;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *checkingActivity;
@property (nonatomic, strong) IBOutlet UILabel *checkingLabel;

//Table view stuff
@property (nonatomic, strong) IBOutlet UITableView *tableView;

@property (nonatomic, strong) IBOutlet UITapGestureRecognizer *tapBehindViewRecognizer;

@end
