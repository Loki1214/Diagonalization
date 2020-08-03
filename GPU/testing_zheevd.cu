#include "../Headers/mersenne_twister.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <cublas_v2.h>
#include <curand_kernel.h>
/* include MTGP host helper functions */
#include <curand_mtgp32_host.h>
/* include MTGP pre-computed parameter sets */
#include <curand_mtgp32dc_p_11213.h>
#include <cuda_runtime_api.h>
#include "magma_v2.h"
#include "magma_lapack.h"

__global__ void SetRandomMatrix(int Dmat, magmaDoubleComplex* mat, curandStateMtgp32_t* MTGPStates_d, int nBlock) {
  int i = blockIdx.x*blockDim.x +threadIdx.x;
  int j = blockIdx.y*blockDim.y +threadIdx.y;
  //int blockId = blockIdx.x +nBlock*blockIdx.y;

  if( i<Dmat && j<Dmat ){
    double rand1 = curand_normal_double(&MTGPStates_d[0]) /sqrt(2.0);
    double rand2 = curand_normal_double(&MTGPStates_d[0]) /sqrt(2.0);
    //printf("%+.4lf, %+.4lf\n", rand1, rand2);

    if(i == j) mat[i +Dmat*j] = MAGMA_Z_MAKE(sqrt(2.0)*rand1,0);
    else if(i < j) {
      mat[i +Dmat*j] = MAGMA_Z_MAKE(rand1,rand2);
      mat[j +Dmat*i] = MAGMA_Z_CONJ(mat[i +Dmat*j]);
    }
  }
}

int main(int argc, char **argv) {
    if(argc != 2) {
      fprintf(stderr, "Usage: 1.This 2.Dmat\n");
      exit(1);
    }

    const int Dmat = atoi(argv[1]);
    int nThread = (int)sqrt(1024);
    int nBlock = (int)Dmat/nThread;
    if( Dmat%nThread != 0 ) nBlock += 1;
    printf("nBlock=%d, nThread=%d *%d=%d\n", nBlock, nThread, nThread, nThread*nThread);
  
    dim3 dimGrid(nBlock, nBlock, 1);
    dim3 dimBlock(nThread, nThread, 1);

    const unsigned long long seed = 0;
    curandStateMtgp32 *MTGPStates_d;
    mtgp32_kernel_params *KernelParams_d;
    //curandGenerator_t generator;
    //curandCreateGenerator(&generator, CURAND_RNG_PSEUDO_MTGP32);
    //curandSetPseudoRandomGeneratorSeed(generator, seed);

    void (*po)(int, magmaDoubleComplex*, curandStateMtgp32_t*, int);
    po = SetRandomMatrix;
    struct cudaFuncAttributes attr;
    cudaFuncGetAttributes(&attr, po);
    printf("constSizeBytes     = %d\n", attr.constSizeBytes);
    printf("maxThreadsPerBlock = %d\n", attr.maxThreadsPerBlock);
    
      
    magma_init();
    magmaDoubleComplex *mat_d, *EigenVectors_d, *temp_d;
    double *w, *rwork;
    magmaDoubleComplex *wA, *work;
    magma_int_t lwork;
    magma_int_t lrwork = 1+5*Dmat+2*Dmat*Dmat;
    magma_int_t *iwork;
    magma_int_t liwork = 3+5*Dmat;
    magma_int_t info;
    magma_int_t nb = magma_get_zhetrd_nb(Dmat);

    struct timespec start_time, end_time;
    clock_t start, end;

    int temp1 = Dmat +Dmat*nb;
    int temp2 = 2*Dmat+Dmat*Dmat;
    if(temp1 < temp2) lwork = temp2;
    else lwork = temp1;

    magma_queue_t queue=NULL;
    magma_int_t dev = 0;
    magma_queue_create( dev, &queue );
    
    magma_zmalloc( &mat_d, Dmat*Dmat );
    magma_zmalloc( &EigenVectors_d, Dmat*Dmat );
    magma_zmalloc( &temp_d, Dmat*Dmat );

    magma_dmalloc_cpu( &w, Dmat );
    magma_zmalloc_cpu( &wA, Dmat*Dmat );
    magma_zmalloc_cpu( &work, lwork );
    magma_dmalloc_cpu( &rwork, lrwork );
    magma_imalloc_cpu( &iwork, liwork );
    
    cudaMalloc( (void**)&MTGPStates_d, nBlock*nBlock *sizeof(curandStateMtgp32) );
    cudaMalloc( (void**)&KernelParams_d, sizeof(mtgp32_kernel_params) );
    cudaMemset( MTGPStates_d, 0, nBlock*nBlock *sizeof(curandStateMtgp32) );

    curandMakeMTGP32Constants(mtgp32dc_params_fast_11213, KernelParams_d);
    curandMakeMTGP32KernelState(MTGPStates_d, mtgp32dc_params_fast_11213, KernelParams_d, 1, seed);
    SetRandomMatrix<<<dimGrid,dimBlock>>>(Dmat, mat_d, MTGPStates_d, nBlock);
    //magma_zprint_gpu(Dmat, Dmat, mat_d, Dmat, queue); 
    magma_zcopymatrix(Dmat, Dmat, mat_d, Dmat, EigenVectors_d, Dmat, queue);

    start = clock();
    clock_gettime(CLOCK_REALTIME, &start_time);
    magma_zheevd_gpu(MagmaVec, MagmaUpper, Dmat, EigenVectors_d, Dmat, w, wA, Dmat, work, lwork, rwork, lrwork, iwork, liwork, &info);
    
    magmaDoubleComplex alpha = MAGMA_Z_MAKE(1,0);
    magmaDoubleComplex beta  = MAGMA_Z_MAKE(0,0);
    magma_zhemm(MagmaLeft, MagmaUpper, Dmat, Dmat, alpha, mat_d, Dmat, EigenVectors_d, Dmat, beta, temp_d, Dmat, queue);
    //magma_zgemm(MagmaConjTrans, MagmaNoTrans, Dmat, Dmat, Dmat, alpha, EigenVectors_d, Dmat, temp_d, Dmat, beta, mat_d, Dmat, queue);
    /*
    magma_zprint_gpu(Dmat, Dmat, mat_d, Dmat, queue);
    magma_dprint(1, Dmat, w, 1);
    */

    end = clock();
    clock_gettime(CLOCK_REALTIME, &end_time);

    unsigned int sec;
    int nsec;
    double d_sec;
    sec = end_time.tv_sec - start_time.tv_sec;
    nsec = end_time.tv_nsec - start_time.tv_nsec;
    d_sec = (double)sec +(double)nsec / (1000 * 1000 * 1000);
    fprintf(stderr, "%d %f %f\n", Dmat, (double)(end-start)/CLOCKS_PER_SEC, d_sec);
    
    magma_queue_destroy(queue);
    magma_free(mat_d);
    magma_free(EigenVectors_d);
    magma_free(temp_d);

    magma_free_cpu(w);
    magma_free_cpu(wA);
    magma_free_cpu(work);
    magma_free_cpu(rwork);
    magma_free_cpu(iwork);

    cudaFree(MTGPStates_d);
    cudaFree(KernelParams_d);

    magma_finalize();
    //curandDestroyGenerator(generator);
    
    return 0;
}
