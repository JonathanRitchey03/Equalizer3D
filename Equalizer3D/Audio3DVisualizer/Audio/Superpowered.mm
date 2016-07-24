#import "Audio3DVisualizer-Bridging-Header.h"
#import "SuperpoweredIOSAudioIO.h"
#include "SuperpoweredBandpassFilterbank.h"
#include "SuperpoweredSimple.h"

@implementation Superpowered {
    SuperpoweredIOSAudioIO *audioIO;
    SuperpoweredBandpassFilterbank *filters;
    float bands[128][NUM_BANDS];
    unsigned int samplerate, bandsWritePos, bandsReadPos, bandsPos, lastNumberOfSamples;
}

static bool audioProcessing(void *clientdata, float **buffers, unsigned int inputChannels, unsigned int outputChannels, unsigned int numberOfSamples, unsigned int samplerate, uint64_t hostTime) {
    __unsafe_unretained Superpowered *self = (__bridge Superpowered *)clientdata;
    if (samplerate != self->samplerate) {
        self->samplerate = samplerate;
        self->filters->setSamplerate(samplerate);
    };

    // Mix the non-interleaved input to interleaved.
    float interleaved[numberOfSamples * 2 + NUM_BANDS*2];
    SuperpoweredInterleave(buffers[0], buffers[1], interleaved, numberOfSamples);

    // Get the next position to write.
    unsigned int writePos = self->bandsWritePos++ & 127;
    memset(&self->bands[writePos][0], 0, NUM_BANDS * sizeof(float));

    // Detect frequency magnitudes.
    float peak, sum;
    self->filters->process(interleaved, &self->bands[writePos][0], &peak, &sum, numberOfSamples);

    // Update position.
    self->lastNumberOfSamples = numberOfSamples;
    __sync_synchronize();
    __sync_fetch_and_add(&self->bandsPos, 1);
    return false;
}

- (float) frequency:(float)n {
    /*
     These are found using
     
     frequency \displaystyle={440}\times{2}^{{{n}\text{/}{12}}}=440×2
     ​n/12
     ​​ 
     for \displaystyle{n}=-{21},-{19},\ldots,{27}n=−21,−19,…,27
     */
    n -= 35;
    float f = 440 * pow(2, n / 12.0);
    return f;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    for ( int i = 0; i < NUM_BANDS; i++ ) {
        NSLog(@"i %@ freq %@", @(i), @([self frequency:i * BAND_STEP]));
    }
    samplerate = 44100;
    bandsWritePos = bandsReadPos = bandsPos = lastNumberOfSamples = 0;
    memset(bands, 0, 128 * NUM_BANDS * sizeof(float));

    float newFrequencies[NUM_BANDS]; /* = {
//        16.35, // 1
//        17.32, // 2
//        18.35, // 3
//        19.45, // 4
//        20.60, // 5
//        21.83, // 6
//        23.12, // 7
//        24.50, // 8
//        25.96, // 9
//        27.50, // 10
//        29.14, // 11
//        30.87, // 12
//        32.70, // 13
//        34.65, // 14
//        36.71, // 15
//        38.89, // 16
//        41.20, // 17
//        43.65, // 18
//        46.25, // 19
//        49.00, // 20
//        51.91, // 21
        55.00,
        58.27,
        61.74,
        65.41,
        69.30,
        73.42,
        77.78,
        82.41,
        87.31,
        92.50,
        98.00,
        103.83,
        110.00,
        116.54,
        123.47,
        130.81,
        138.59,
        146.83,
        155.56,
        164.81,
        174.61,
        185.00,
        196.00,
        207.65,
        220.00,
        233.08,
        246.94,
        261.63,
        277.18,
        293.66,
        311.13,
        329.63,
        349.23,
        369.99,
        392.00,
        415.30,
        440.00,
        466.16,
        493.88,
        523.25,
        554.37,
        587.33,
        622.25,
        659.25,
        698.46,
        739.99,
        783.99,
        830.61,
        880.00,
        932.33,
        987.77,
        1046.50,
        1108.73,
        1174.66,
        1244.51,
        1318.51,
        1396.91,
        1479.98,
        1567.98,
        1661.22,
        1760.00,
        1864.66,
        1975.53,
        2093.00,
        2217.46,
        2349.32,
        2489.02,
        2637.02,
        2793.83,
        2959.96,
        3135.96,
        3322.44,
        3520.00,
        3729.31,
        3951.07,
        4186.01,
        4434.92,
        4698.63,
        4978.03,
        5274.04,
        5587.65,
        5919.91,
        6271.93,
        6644.88,
        7040.00,
        7458.62,
        7902.13
    };*/
    float widths[NUM_BANDS];
    for ( int i = 0; i < NUM_BANDS; i++ ) {
        newFrequencies[i] = [self frequency:i * BAND_STEP];
    }
    
    for ( int i = 0; i < NUM_BANDS; i++ ) {
        widths[i] = 1.0 / 12.0 * BAND_STEP;
    }
    filters = new SuperpoweredBandpassFilterbank(NUM_BANDS, newFrequencies, widths, samplerate);

    audioIO = [[SuperpoweredIOSAudioIO alloc] initWithDelegate:(id<SuperpoweredIOSAudioIODelegate>)self preferredBufferSize:12 preferredMinimumSamplerate:44100 audioSessionCategory:AVAudioSessionCategoryRecord channels:2 audioProcessingCallback:audioProcessing clientdata:(__bridge void *)self];
    [audioIO start];

    return self;
}

- (void)dealloc {
    delete filters;
    audioIO = nil;
}

- (void)interruptionStarted {}
- (void)interruptionEnded {}
- (void)recordPermissionRefused {}
- (void)mapChannels:(multiOutputChannelMap *)outputMap inputMap:(multiInputChannelMap *)inputMap externalAudioDeviceName:(NSString *)externalAudioDeviceName outputsAndInputs:(NSString *)outputsAndInputs {}

/*
 It's important to understand that the audio processing callback and the screen update (getFrequencies) are never in sync. 
 More than 1 audio processing turns may happen between two consecutive screen updates.
 */

- (void)getFrequencies:(float *)freqs {
    memset(freqs, 0, NUM_BANDS * sizeof(float));
    unsigned int currentPosition = __sync_fetch_and_add(&bandsPos, 0);
    if (currentPosition > bandsReadPos) {
        unsigned int positionsElapsed = currentPosition - bandsReadPos;
        float multiplier = 1.0f / float(positionsElapsed * lastNumberOfSamples);
        while (positionsElapsed--) {
            float *b = &bands[bandsReadPos++ & 127][0];
            for (int n = 0; n < NUM_BANDS; n++) freqs[n] += b[n] * multiplier;
        }
    }
}

@end
