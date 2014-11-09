//
//  TLHMViewController.m
//  HelloMyo
//
//  Copyright (c) 2013 Thalmic Labs. All rights reserved.
//  Distributed under the Myo SDK license agreement. See LICENSE.txt.
//

#import "TLHMViewController.h"


double lowerBound = -.9;
double upperBound = .2;
double accUpperBound = 1.5;
double accLowerBound = .5;
double twistBound = 2;
double motionRange;
float magnitude;

TLMMyo *myo;
bool atTop = false;
bool atBottom = TRUE;
bool error = false;
int count = 0;
NSTimeInterval lastVibrationTime = 0;
NSTimeInterval lastTwistTime = 0;

bool exerciseInProgress = false;




@interface TLHMViewController ()

@property (weak, nonatomic) IBOutlet UIProgressView *rotationProgressBar;

@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (strong, nonatomic) TLMPose *currentPose;

@property (weak, nonatomic) IBOutlet UILabel *counterLabel;

- (IBAction)didTapSettings:(id)sender;

@end

@implementation TLHMViewController

#pragma mark - View Lifecycle

- (id)init {
    // Initialize our view controller with a nib (see TLHMViewController.xib).
    self = [super initWithNibName:@"TLHMViewController" bundle:nil];
    motionRange = upperBound - lowerBound;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Data notifications are received through NSNotificationCenter.
    // Posted whenever a TLMMyo connects
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didConnectDevice:)
                                                 name:TLMHubDidConnectDeviceNotification
                                               object:nil];
    // Posted whenever a TLMMyo disconnects
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didDisconnectDevice:)
                                                 name:TLMHubDidDisconnectDeviceNotification
                                               object:nil];
    // Posted whenever the user does a Sync Gesture, and the Myo is calibrated
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didRecognizeArm:)
                                                 name:TLMMyoDidReceiveArmRecognizedEventNotification
                                               object:nil];
    // Posted whenever Myo loses its calibration (when Myo is taken off, or moved enough on the user's arm)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didLoseArm:)
                                                 name:TLMMyoDidReceiveArmLostEventNotification
                                               object:nil];
    // Posted when a new orientation event is available from a TLMMyo. Notifications are posted at a rate of 50 Hz.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveOrientationEvent:)
                                                 name:TLMMyoDidReceiveOrientationEventNotification
                                               object:nil];
    // Posted when a new accelerometer event is available from a TLMMyo. Notifications are posted at a rate of 50 Hz.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveAccelerometerEvent:)
                                                 name:TLMMyoDidReceiveAccelerometerEventNotification
                                               object:nil];
    // Posted when a new pose is available from a TLMMyo
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceivePoseChange:)
                                                 name:TLMMyoDidReceivePoseChangedNotification
                                               object:nil];

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - NSNotificationCenter Methods

- (void)didConnectDevice:(NSNotification *)notification {
    
    //Get myo object
    myo = [[TLMHub sharedHub] myoDevices][0];

    // Set the text of the armLabel to "Perform the Sync Gesture"
    self.statusLabel.text = @"Twist arm to start";

    // Show the counter
    self.counterLabel.text = @"0";
    [self.counterLabel setHidden: YES];
    [self.rotationProgressBar setHidden:YES];

}

- (void)didDisconnectDevice:(NSNotification *)notification {
    // Change the text of our label when the Myo has disconnected.
    self.statusLabel.textColor = [UIColor darkGrayColor];
    self.statusLabel.text = @"No Myo Connected";

    // Hide the acceleration progress bar
    [self.rotationProgressBar setHidden:YES];
}

- (void)didRecognizeArm:(NSNotification *)notification {
    // Retrieve the arm event from the notification's userInfo with the kTLMKeyArmRecognizedEvent key.
    TLMArmRecognizedEvent *armEvent = notification.userInfo[kTLMKeyArmRecognizedEvent];

    // Update the armLabel with arm information
    NSString *armString = armEvent.arm == TLMArmRight ? @"Right" : @"Left";
    NSString *directionString = armEvent.xDirection == TLMArmXDirectionTowardWrist ? @"Toward Wrist" : @"Toward Elbow";

    self.statusLabel.textColor = [UIColor darkGrayColor];
}

- (void)didLoseArm:(NSNotification *)notification{
    // Reset the armLabel and helloLabel
    self.statusLabel.text = @"Twist arm to start";
    self.statusLabel.textColor = [UIColor darkGrayColor];

    
    //synced = false;
    exerciseInProgress = false;
}

- (void)didReceiveOrientationEvent:(NSNotification *)notification {
    // Retrieve the orientation from the NSNotification's userInfo with the kTLMKeyOrientationEvent key.
    TLMOrientationEvent *orientationEvent = notification.userInfo[kTLMKeyOrientationEvent];

    // Create Euler angles from the quaternion of the orientation.
    TLMEulerAngles *angles = [TLMEulerAngles anglesWithQuaternion:orientationEvent.quaternion];

    //Check the rotation progress
    if(exerciseInProgress){
        double percent = (angles.pitch.radians - lowerBound )/motionRange;
        self.rotationProgressBar.progress = percent;
    
        if(percent > 1 && !atTop){
            atTop = true;
            atBottom = false;
        }else if(percent < 0 && !atBottom){
            atTop = false;
            atBottom = true;
            [self incrementCount];

        }
    }
    
    //Check if arm is twisted
    if(angles.roll.radians > twistBound || angles.roll.radians < -twistBound){
        if(angles.pitch.radians > .4 && exerciseInProgress){
            NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
            if(currentTime - lastVibrationTime > 1.5){
                [myo vibrateWithLength: TLMVibrationLengthShort];
                lastVibrationTime = currentTime;
            }
        }else{
            NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
            if(currentTime - lastTwistTime > 1){
                if(exerciseInProgress){
                    exerciseInProgress = false;
                    [self resetCount];
                    self.statusLabel.textColor = [UIColor darkGrayColor];
                    self.statusLabel.text = @"Twist Arm to start!";
                    
                }else{
                    exerciseInProgress = true;
                    self.statusLabel.text = @"Go!";
                    self.statusLabel.textColor = [UIColor greenColor];
                    [self.rotationProgressBar setHidden: NO];
                    [self.counterLabel setHidden: NO];
                    
                }
                lastTwistTime = currentTime;
            }
        }
    }
    

    
}

//Counter Functions

- (void)incrementCount{
    count ++;
    [self.counterLabel setText: @(count).stringValue];
}
- (void)resetCount{
    count = 0;
    [self.counterLabel setText: @(count).stringValue];
}



- (void)didReceiveAccelerometerEvent:(NSNotification *)notification {
    // Retrieve the accelerometer event from the NSNotification's userInfo with the kTLMKeyAccelerometerEvent.
    TLMAccelerometerEvent *accelerometerEvent = notification.userInfo[kTLMKeyAccelerometerEvent];

    // Get the acceleration vector from the accelerometer event.
    GLKVector3 accelerationVector = accelerometerEvent.vector;

    // Calculate the magnitude of the acceleration vector.
    magnitude = GLKVector3Length(accelerationVector);

    //NSLog(@"Acceleration mag %f", magnitude * 100);
    NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];

    //Check if accelerating too much
    if(exerciseInProgress){
        if (magnitude > accUpperBound || magnitude < accLowerBound){
            if(currentTime - lastVibrationTime > 1.5){
                [myo vibrateWithLength: TLMVibrationLengthShort];
                lastVibrationTime = currentTime;
            }
            self.statusLabel.text = @"Slow down!";
            self.statusLabel.textColor = [UIColor redColor];
        }else{
            if(currentTime - lastVibrationTime > 1.5){
                self.statusLabel.text = @"Go!";
                self.statusLabel.textColor = [UIColor greenColor];
            }
        }
    }

    /* Note you can also access the x, y, z values of the acceleration (in G's) like below
     float x = accelerationVector.x;
     float y = accelerationVector.y;
     float z = accelerationVector.z;
     */
}

- (void)didReceivePoseChange:(NSNotification *)notification {
    // Retrieve the pose from the NSNotification's userInfo with the kTLMKeyPose key.
    TLMPose *pose = notification.userInfo[kTLMKeyPose];
    self.currentPose = pose;

    // Handle the cases of the TLMPoseType enumeration, and change the color of helloLabel based on the pose we receive.
    switch (pose.type) {
        case TLMPoseTypeUnknown:
        case TLMPoseTypeRest:
            break;
        case TLMPoseTypeFist:
            break;
        case TLMPoseTypeWaveIn:
            [myo vibrateWithLength: TLMVibrationLengthShort];
            break;
        case TLMPoseTypeWaveOut:
            [myo vibrateWithLength: TLMVibrationLengthShort];
            break;
        case TLMPoseTypeFingersSpread:
            break;
        case TLMPoseTypeThumbToPinky:
            break;
    }
}

- (IBAction)didTapSettings:(id)sender {
    // Note that when the settings view controller is presented to the user, it must be in a UINavigationController.
    UINavigationController *controller = [TLMSettingsViewController settingsInNavigationController];
    // Present the settings view controller modally.
    [self presentViewController:controller animated:YES completion:nil];
}

@end
