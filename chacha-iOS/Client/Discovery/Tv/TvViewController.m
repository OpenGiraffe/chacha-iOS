//
//  ViewController.m
//  myrtmp
//
//  Created by liuf on 16/7/15.
// 
//

#import "TvViewController.h"
#import "ApxRTC_RTMPService.h"
#import "ApxRTC_ACPService.h"
#import "FilterSelectModalView.h"
@interface TvViewController ()<ApxRTC_ServiceDelegate,FilterSelectModalViewDelegate>

@property (weak,nonatomic) IBOutlet UILabel *statusLabel;
@property (weak,nonatomic) IBOutlet UIView  *preveiw;
@property (weak,nonatomic) IBOutlet UIView  *controlView;
@property (weak,nonatomic) IBOutlet UIButton *palyButton;
@property (strong,nonatomic) IBOutlet UISlider *slider;

@end

@implementation TvViewController
{
    ApxRTC_ACPService *acpService;
    UIButton *_statusBtn;
    BOOL _isOpenFlash;
    BOOL _isStarted;
    BOOL _isFrontCamera;
    FilterSelectModalView *_filterSelectView;
    LFVideoConfig *_videoConfig;
    NSString *_streamProtocol;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil streamProtocol:(NSString *)streamProtocol{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _streamProtocol = streamProtocol;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupRTCServiceWithType:_streamProtocol];
}

-(void) setupRTCServiceWithType:(NSString *)type{
    _isFrontCamera=YES;
    _videoConfig=[[LFVideoConfig alloc] init:LFVideoConfigQuality_Hight3 isLandscape:NO];
    
    if([type isEqualToString:@"rtmp"]){
        acpService=[ApxRTC_RTMPService sharedInstance];
        [acpService setupWithVideoConfig:_videoConfig
                              audioConfig:[LFAudioConfig defaultConfig]
                                  preview:_preveiw];
        acpService.delegate=self;
    }else if([type isEqualToString:@"acp"]){
        acpService=[ApxRTC_ACPService sharedInstance];
        [acpService setupWithVideoConfig:_videoConfig
                             audioConfig:[LFAudioConfig acpConfig]
                                 preview:_preveiw];
        acpService.delegate=self;
    }
    [self.view addSubview:_statusBtn];
    _filterSelectView=[[NSBundle mainBundle] loadNibNamed:@"FilterSelectModalView" owner:nil options:nil][0];
    _filterSelectView.delegate=self;
}

-(void)addLogo{
    UIImageView *logoView=[[UIImageView alloc] initWithFrame:CGRectMake(0, 56, 80, 17)];
    logoView.image=[UIImage imageNamed:@"logo"];
    [acpService setLogoView:logoView];
}
-(IBAction)toggleCapture:(id)sender{
    if(!_isStarted){
        [self addLogo];
        [_palyButton setImage:[UIImage imageNamed:@"capture_stop_button"] forState:(UIControlStateNormal)];
        ((ApxRTC_RTMPService *)acpService).urlParser=[[LFRtmpUrlParser alloc] initWithUrl:@"rtmp://192.168.3.115/live/jing" port:1935];
        [acpService start];
    }else{
        [_palyButton setImage:[UIImage imageNamed:@"capture_button"] forState:(UIControlStateNormal)];
        _statusLabel.text=@"未连接";
        [acpService stop];
    }
    _isStarted=!_isStarted;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if(!_isStarted){
        if([acpService isLandscape]){
            UIInterfaceOrientation orientation=[[UIApplication sharedApplication] statusBarOrientation];
            if(orientation==UIInterfaceOrientationPortrait||orientation==UIInterfaceOrientationPortraitUpsideDown){
                _videoConfig=[[LFVideoConfig alloc] init:LFVideoConfigQuality_Hight3 isLandscape:NO];
                [acpService setVideoConfig:_videoConfig];
                [acpService setOrientation:orientation];
            }
            
        }else{
            UIInterfaceOrientation orientation=[[UIApplication sharedApplication] statusBarOrientation];
            if(orientation==UIInterfaceOrientationLandscapeLeft||orientation==UIInterfaceOrientationLandscapeRight){
                _videoConfig=[[LFVideoConfig alloc] init:LFVideoConfigQuality_Hight3 isLandscape:YES];
                [acpService setVideoConfig:_videoConfig];
                [acpService setOrientation:orientation];
            }
        }
    }
}

-(IBAction)toggleFlash:(id)sender{
    [acpService setIsOpenFlash:!acpService.isOpenFlash];
}

-(IBAction)toggleCamera:(id)sender{
    if(_isFrontCamera){
        [acpService setDevicePosition:AVCaptureDevicePositionBack];
    }else{
         [acpService setDevicePosition:AVCaptureDevicePositionFront];
    }
    _isFrontCamera=!_isFrontCamera;
}

-(IBAction)back:(id)sender{
    [acpService quit];
    [self.navigationController popViewControllerAnimated:YES];
}

-(IBAction)selectFilter:(id)sender{
    [_filterSelectView show:NO];
    
}
#pragma mark slider actions

- (IBAction)beginScrubbing:(id)sender{
    
}
- (IBAction)scrub:(id)sender{
    __weak UISlider *slider=_slider;
    [acpService setVideoZoomScale:[_slider value] andError:^{
        [slider setValue:1.0 animated:YES];
    }];
}
- (IBAction)endScrubbing:(id)sender{
    
}

#pragma mark FilterSelectModalViewDelegate

-(void)onDidTouchFilter:(int)filterType{
    [acpService setFilterType:filterType];
}

#pragma mark LFRtmpServiceDelegate
/**
 *  当rtmp状态发生改变时的回调
 *
 *  @param status 状态描述符
 */
-(void)onStatusChange:(ApxStreamStatus)status message:(id)message{
    switch (status) {
        case ApxStreamStatusConnectionFail:
        {
            [_statusLabel setText:@"连接失败!重连中..."];
        }
            break;
        case ApxStreamStatusPublishSending:
        {
            [_statusLabel setText:@"流发布中"];
        }
            break;
        case ApxStreamStatusPublishReady:
        {
           [_statusLabel setText:@"流发布成功，开始推流"];
        }
            break;
        case ApxStreamStatusPublishFail:
        {
           [_statusLabel setText:@"流发布失败，restart"];
           [acpService reStart];
        }
            break;
        case ApxStreamStatusPublishFailBadName:
        {
            [_statusLabel setText:@"错误的流名"];
            //这种情况可能是推流地址过期造成的，可获取新的推流地址，重新开始连接
            //rtmpService.urlParser=[[LFRtmpUrlParser alloc] initWithUrl:@"新推流地址" port:1935];
            [acpService reStart];
        }
            break;
        default:
            break;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.hidden=YES;
}

-(void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    self.navigationController.navigationBar.hidden=NO;
}

@end
