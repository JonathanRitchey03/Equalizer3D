// Adapted from SuperpoweredFrequencyDomain example from Superpowered SDK.
// NUM_BANDS was changed from 8 to 1280. And the width was adjusted accordingly.
// See https://github.com/superpoweredSDK/Low-Latency-Android-Audio-iOS-Audio-Engine/tree/master/SuperpoweredFrequencyDomain/SuperpoweredFrequencyDomain

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

    float newFrequencies[NUM_BANDS];
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
