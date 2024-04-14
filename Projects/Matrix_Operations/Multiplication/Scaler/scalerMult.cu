#include <cuda_runtime.h>
#include <stdio.h>
#include <sys/time.h>

#define CHECK(call){                                                                    \
    const cudaError_t error = call;                                                     \
    if (error != cudaSuccess){                                                          \
        printf("Error#: %s:%d \n", __FILE__, __LINE__);                                    \
        printf("\t code:%d, reason: %s\n", error, cudaGetErrorString(error));              \
        exit(1);                                                                        \
    }                                                                                   \
}   

double cpuSecond() {
    struct timeval tp;
    gettimeofday(&tp,NULL);
    return ((double)tp.tv_sec + (double)tp.tv_usec*1.e-6);
}


void sumMatrixOnHost(float *A, float *B, float *C, const int nx, const int ny){
    float *ia = A;
    float ib = *B;
    float *ic = C;

    for(int iy=0; iy<ny; iy++){
        for(int ix=0; ix<nx; ix++){
            ic[ix] = ia[ix] * ib;
        }
        ia += nx; ic += nx;
    }
}

__global__ void sumMatrixOnDevice(float *MatA, float *scaler, float *MatC, const int nx, const int ny){
    unsigned int ix = threadIdx.x + blockIdx.x * blockDim.x;
    unsigned int iy = threadIdx.y + blockIdx.y * blockDim.y;

    unsigned int idx = iy * nx + ix;

    float scaler_val = *scaler;

    if(ix < nx && iy < ny)
        MatC[idx] = MatA[idx] * scaler_val;
}

void initialData(float *ip,int size) {
    // generate different seed for random number
    time_t t;
    srand((unsigned) time(&t));
    for (int i=0; i<size; i++) {
        ip[i] = (float)( rand() & 0xFF )/10.0f;
    }
}

void checkResult(float *hostRef, float *gpuRef, const int N) {
    double epsilon = 1.0e-9;
    bool match = 1;

    for(int i=0; i<N; i++){
        if(abs(hostRef[i] - gpuRef[i]) > epsilon){
            match = 0;
            printf("Arrays do not match! \n");
            printf("Host %5.2f GPU %5.2f at current %d\n", hostRef[i], gpuRef[i], i);
            break;
        }
    }

    if(match) printf("Arrays match! \n\n");
}

int main(int argc, char **argv){
    printf("%s Starting ... \n", argv[0]);

    // Get device Info
    int dev = 0;
    cudaDeviceProp deviceProp;
    CHECK(cudaGetDeviceProperties(&deviceProp, dev));
    printf("Using Device %d: %s\n", dev, deviceProp.name);
    CHECK(cudaSetDevice(dev));

    int nx = 1 << 14;
    int ny = 1 << 14;

    int nxy = nx * ny;
    int nBytes = nxy * sizeof(float);
    printf("Matrix size: (%d, %d) \n", nx, ny);

    // Malloc host memory
    float *h_A, *h_scaler, *hostRef, *gpuRef;
    h_A = (float *)malloc(nBytes);
    h_scaler = (float *)malloc(sizeof(float));
    hostRef = (float *)malloc(nBytes);
    gpuRef = (float *)malloc(nBytes);

    // initialize data at host side
    double iStart = cpuSecond();
    initialData (h_A, nxy);
    *h_scaler = 17.;
    double iElaps = cpuSecond() - iStart;
    memset(hostRef, 0, nBytes);
    memset(gpuRef, 0, nBytes);
    // add matrix at host side for result checks
    iStart = cpuSecond();
    sumMatrixOnHost (h_A, h_scaler, hostRef, nx,ny);
    iElaps = cpuSecond() - iStart;
    printf("sumMatrixOnCPU elapsed %f sec\n", iElaps);

    // Intialise data on Host
    float *d_MatA, *d_scaler, *d_MatC;
    cudaMalloc((void **)&d_MatA, nBytes);
    cudaMalloc((void **)&d_scaler, nBytes);
    cudaMalloc((void **)&d_MatC, nBytes);

    cudaMemcpy(d_MatA, h_A, nBytes, cudaMemcpyHostToDevice);
    cudaMemcpy(d_scaler, h_scaler, sizeof(float), cudaMemcpyHostToDevice);

    // Invoke Kernal 
    int dimx = 32;
    int dimy = 16;

    dim3 block(dimx, dimy);
    dim3 grid((nx + block.x -1) / block.x, ((ny + block.y -1) / block.y));

    iStart = cpuSecond();
    sumMatrixOnDevice <<<grid, block>>>(d_MatA, d_scaler, d_MatC, nx, ny);
    cudaDeviceSynchronize();
    iElaps = cpuSecond() - iStart;

    printf("sumMatrixOnGPU2D <<<(%d,%d), (%d,%d)>>> elapsed %f sec\n", grid.x,
            grid.y, block.x, block.y, iElaps);


    cudaMemcpy(gpuRef, d_MatC, nBytes, cudaMemcpyDeviceToHost);

    // check device results
    checkResult(hostRef, gpuRef, nxy);

    // free device global memory
    cudaFree(d_MatA);
    cudaFree(d_scaler);
    cudaFree(d_MatC);
    // free host memory
    free(h_A);
    free(h_scaler);
    free(hostRef);
    free(gpuRef);
    // reset device
    cudaDeviceReset();

    return 0;
}