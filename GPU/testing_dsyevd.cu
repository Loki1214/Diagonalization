#include "../Headers/mersenne_twister.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <cublas_v2.h>
//#include <cuda_runtime_api.h>
#include "magma_v2.h"
#include "magma_lapack.h"

int main(int argc, char **argv) {
    if(argc != 2) {
      fprintf(stderr, "Usage: 1.This 2.Dmat\n");
      exit(1);
    }
    const int seed = 0;
    init_genrand(seed);

    magma_init();
    const int Dmat = atoi(argv[1]);
    double *mat_h, *mat_d, *EigenVectors_d, *temp_d;
    double *w, *wA, *work;
    magma_int_t lwork;
    int *iwork;
    magma_int_t liwork = 3+5*Dmat;
    magma_int_t info;
    magma_int_t nb = magma_get_dsytrd_nb(Dmat);

    struct timespec start_time, end_time;
    clock_t start, end;

    int temp1 = 2*Dmat +Dmat*nb;
    int temp2 = 1+6*Dmat+2*Dmat*Dmat;
    if(temp1 < temp2) lwork = temp2;
    else lwork = temp1;

    magma_queue_t queue=NULL;
    magma_int_t dev = 0;
    magma_queue_create( dev, &queue );

    magma_dmalloc_pinned( &mat_h, Dmat*Dmat );
    magma_dmalloc( &mat_d, Dmat*Dmat );
    magma_dmalloc( &EigenVectors_d, Dmat*Dmat );
    magma_dmalloc( &temp_d, Dmat*Dmat );
    magma_dmalloc_cpu( &w, Dmat );
    magma_dmalloc_cpu( &wA, Dmat*Dmat );
    magma_dmalloc_cpu( &work, lwork );
    magma_imalloc_cpu( &iwork, liwork );

    for(int i=0;i < Dmat; ++i) {
      mat_h[i+Dmat*i] = genrand_real3();
      for(int j=0;j < i; ++j) {
	mat_h[i+Dmat*j] = genrand_real3();
	mat_h[j+Dmat*i] = mat_h[i+Dmat*j];
      }
    }
    //magma_dprint(Dmat, Dmat, mat_h, Dmat);

    magma_dsetmatrix(Dmat, Dmat, mat_h, Dmat, mat_d, Dmat, queue);
    magma_dcopymatrix(Dmat, Dmat, mat_d, Dmat, EigenVectors_d, Dmat, queue);

    start = clock();
    clock_gettime(CLOCK_REALTIME, &start_time);
    magma_dsyevd_gpu(MagmaVec, MagmaUpper, Dmat, EigenVectors_d, Dmat, w, wA, Dmat, work, lwork, iwork, liwork, &info);
    end = clock();
    clock_gettime(CLOCK_REALTIME, &end_time);

    unsigned int sec;
    int nsec;
    double d_sec;
    sec = end_time.tv_sec - start_time.tv_sec;
    nsec = end_time.tv_nsec - start_time.tv_nsec;
    d_sec = (double)sec +(double)nsec / (1000 * 1000 * 1000);
    fprintf(stdout, "%d %f %f\n", Dmat, (double)(end-start)/CLOCKS_PER_SEC, d_sec);

//    magma_dsymm(MagmaLeft, MagmaUpper, Dmat, Dmat, 1, mat_d, Dmat, EigenVectors_d, Dmat, 0, temp_d, Dmat, queue);
//    magma_dgemm(MagmaTrans, MagmaNoTrans, Dmat, Dmat, Dmat, 1, EigenVectors_d, Dmat, temp_d, Dmat, 0, mat_d, Dmat, queue);
//    magma_dprint_gpu(Dmat, Dmat, mat_d, Dmat, queue);

    magma_queue_destroy(queue);
    //magma_free_cpu(mat_h);
    //magma_free(mat_d);
    //magma_free_cpu(w);
    //magma_free_cpu(wA);
    //magma_free_cpu(work);
    //magma_free_cpu(iwork);
    return 0;
}
