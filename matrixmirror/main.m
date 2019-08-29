#include <ncurses.h>
#include <pthread.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVCaptureDevice.h>
#import <AVFoundation/AVCaptureInput.h>
#import <AVFoundation/AVCaptureOutput.h>
#import <AVFoundation/AVCaptureSession.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>


static pthread_mutex_t mutex;
static pthread_cond_t condition;
static NSImage *image;


void convertToAscii(CGContextRef bitmap) {
    size_t width = CGBitmapContextGetWidth(bitmap);
    size_t height = CGBitmapContextGetHeight(bitmap);
    uint32_t* pixel = (uint32_t*)CGBitmapContextGetData(bitmap);
    
    char* m = "`^\",:;Il!i~+_-?]}{1)(|/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$";
    unsigned long len = strlen(m);
    
    for (int Y = 0 ; Y < LINES ; Y++) {
        for (int X = 0 ; X < COLS ; X++) {
            
            int X2 = COLS - 1 - X;
            
            unsigned long xStart = (X2 * width) / COLS;
            unsigned long xEnd = ((X2 + 1) * width) / COLS;
            if (xEnd > width) {
                xEnd = width;
            }

            unsigned long yStart = (Y * height) / LINES;
            unsigned long yEnd = ((Y + 1) * height) / LINES;
            if (yEnd > height) {
                yEnd = height;
            }

            unsigned long val = 0;
            int n = 0;
            for (unsigned long y = yStart ; y < yEnd ; y++) {
                for (unsigned long x = xStart ; x < xEnd ; x++) {
                    n++;
                    uint32_t rgba = pixel[y * width + x];
                    uint8_t red   = (rgba & 0x000000ff) >> 0;
                    uint8_t green = (rgba & 0x0000ff00) >> 8;
                    uint8_t blue  = (rgba & 0x00ff0000) >> 16;
                    val += (int)(red * 0.21 + green * 0.72 + blue * 0.07);
                }
            }
            
            val = (val * (len - 1)) / (n * 768);
            char c = m[len - 1 - val];
            mvprintw(Y, X, "%c", c);
        }
    }
    mvprintw(LINES - 1, 0, "  Press space to quit...  ");
    refresh();
}


void processImage(NSImage* image) {
    NSSize imageSize = image.size;
    NSRect imageRect = NSMakeRect(0, 0, imageSize.width, imageSize.height);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL,
                                             imageSize.width,
                                             imageSize.height,
                                             8,
                                             0,
                                             colorSpace,
                                             kCGImageAlphaPremultipliedLast);
    
    NSGraphicsContext* gctx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    
    [NSGraphicsContext setCurrentContext:gctx];
    [image drawInRect:imageRect];
    
    convertToAscii(ctx);
    
    [NSGraphicsContext setCurrentContext:nil];
    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);
}



void captureImage(AVCaptureStillImageOutput *output) {
    [output captureStillImageAsynchronouslyFromConnection:[output connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef  _Nullable imageDataSampleBuffer, NSError * _Nullable error) {

        NSData* jpeg = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation: imageDataSampleBuffer];
        image = [[NSImage alloc] initWithData:jpeg];
        pthread_cond_signal(&condition);
    }];
}



void startCapture() {
    AVCaptureSession *captureSession = [[AVCaptureSession alloc] init];
    
    [captureSession beginConfiguration];
    AVCaptureDevice *videoDevice =
    [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    NSError* outError;
    [videoDevice lockForConfiguration:&outError];
    videoDevice.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    [videoDevice unlockForConfiguration];

    NSError *error;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    [captureSession addInput:input];

    AVCaptureStillImageOutput *output = [[AVCaptureStillImageOutput alloc] init];
    [captureSession addOutput:output];
    
    [captureSession commitConfiguration];
    
    [captureSession startRunning];
    
    initscr();
    WINDOW* window = initscr();
    raw();
    noecho();
    keypad(window, true);
    nodelay(window, true);
    use_default_colors();
    start_color();
    init_pair(1, COLOR_GREEN, COLOR_BLACK);
    attron(COLOR_PAIR(1));
    curs_set(0);
    
    pthread_cond_init(&condition, NULL);
    
    int c;
    captureImage(output);
    while ((c = getch()) != ' ') {
        pthread_cond_wait(&condition, &mutex);
        processImage(image);
        captureImage(output);

    }
    pthread_cond_destroy(&condition);
    delwin(window);
    endwin();
    [captureSession stopRunning];
}


int main(int argc, const char * argv[]) {
    @autoreleasepool {
    }
    
    pthread_mutex_init(&mutex, NULL);

    // Let's ask for permission to use the camera
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo])
    {
        case AVAuthorizationStatusAuthorized:
        {
            break;
        }
        case AVAuthorizationStatusNotDetermined:
        {
            // We use a mutex since the callback is executed on an arbitrary dispatch queue
            pthread_mutex_lock(&mutex);
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (!granted) {
                    fprintf(stderr, "Access to webcam was denied\n");
                    exit(1);
                }
                pthread_mutex_unlock(&mutex);
            }];
            break;
        }
        case AVAuthorizationStatusDenied:
        {
            fprintf(stderr, "Access to webcam was denied\n");
            exit(1);
        }
        case AVAuthorizationStatusRestricted:
        {
            fprintf(stderr, "User is not allowed to access the webcam\n");
            exit(1);
            return 1;
        }
    }
    
    // We can get here either directly because of AVAuthorizationStatusAuthorized or
    // indirectly because of requestAccessForMediaType's callback giving us permission
    // from another thread. We use a mutex lock/unlock sequence to make sure that we only
    // proceed when we do have permission
    pthread_mutex_lock(&mutex);
    pthread_mutex_unlock(&mutex);

    startCapture();
    
    pthread_mutex_destroy(&mutex);
    return 0;
}
