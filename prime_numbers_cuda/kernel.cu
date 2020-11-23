#include <iostream>
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <stdio.h>

#include <time.h>
#include <cstdlib>

using namespace std;
cudaError_t addWithCuda(long long unsigned int liczba, bool *pierwsza);


__global__ void PierwszaCzyZlozona23(long long unsigned int *liczba, bool *pierwsza)
{
	long long unsigned int index = threadIdx.x;
	if (*liczba % (index + 2) == 0)
		*pierwsza = false;
}

__global__ void PierwszaCzyZlozona(long long unsigned int *liczba, bool *pierwsza, long long unsigned int *przesuniecie)
{
	long long unsigned int i = (threadIdx.x + blockDim.x*blockIdx.x + *przesuniecie) * 6;
	if (*liczba % ((i + 5)) == 0) { *pierwsza = false; }
	if (*liczba % ((i + 5) + 2) == 0) { *pierwsza = false; }
}

int main()
{
	// PIERWSZE
	// 2^31-1 = 2147483647
	// 2^61-1 = 2305843009213693951
	// ZLOZONE
	// (2^31-1)^2		= 4611686014132420609
	// (2^31-1)(2^13-1) = 17590038552577


	unsigned long long int liczba = 0;
	bool pierwsza = true;
	time_t startCPU;
	time_t stopCPU;
	time_t startGPU;
	time_t stopGPU;

	cout << "Podaj liczbe" << endl;
	cin >> liczba;

	cout << "SPRAWDZANIE DLA CPU" << endl;
	startCPU = clock();

	if (liczba % 2 == 0) pierwsza = false;
	else if (liczba % 3 == 0) pierwsza = false;

	if (pierwsza)
		for (unsigned long long int i = 5; i <= sqrt(liczba); i = i + 6) {
			if (liczba % i == 0) { pierwsza = false; break; }
			if (liczba % (i + 2) == 0) { pierwsza = false; break; }
		}

	if (pierwsza) {
		cout << "Liczba pierwsza" << endl;
	}
	else {
		cout << "Liczba zlozona" << endl;
	}

	stopCPU = clock();
	double czasCPU = (double)(stopCPU - startCPU) / CLOCKS_PER_SEC;
	cout << "Czas sprawdzania na CPU wynosi: " << czasCPU << endl;

	pierwsza = true;
	cout << "SPRAWDZANIE DLA GPU" << endl;
	startGPU = clock();
	cudaError_t cudaStatus = addWithCuda(liczba, &pierwsza);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "addWithCuda failed!");
		char l;
		cin >> l;
		return 1;
	}

	if (pierwsza) {
		cout << "Liczba pierwsza" << endl;
	}
	else {
		cout << "Liczba zlozona" << endl;
	}

	stopGPU = clock();
	double czasGPU = (double)(stopGPU - startGPU) / CLOCKS_PER_SEC;
	cout << "Czas sprawdzania na GPU wynosi: " << czasGPU << endl;

	double przyspieszenie = (double)(czasCPU / czasGPU);
	cout << "Przyspieszenie na GPU wzglêdem CPU: " << przyspieszenie << endl;
	// cudaDeviceReset must be called before exiting in order for profiling and
	// tracing tools such as Nsight and Visual Profiler to show complete traces.
	cudaStatus = cudaDeviceReset();
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaDeviceReset failed!");
		return 1;
	}

	system("pause");

	return 0;
}

cudaError_t addWithCuda(long long unsigned int liczba, bool *pierwsza)
{
	long long unsigned int *dev_liczba = 0;
	bool				   *dev_pierwsza = 0;
	long long unsigned int	przesuniecie = 0;
	long long unsigned int *dev_przesuniecie = 0;

	cudaError_t cudaStatus;

	cudaStatus = cudaSetDevice(0);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
		goto Error;
	}

	cudaStatus = cudaMalloc((void**)&dev_liczba, sizeof(long long unsigned int));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMalloc failed!");
		goto Error;
	}

	cudaStatus = cudaMalloc((void**)&dev_pierwsza, sizeof(bool));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMalloc failed!");
		goto Error;
	}

	cudaStatus = cudaMemcpy(dev_liczba, &liczba, sizeof(long long unsigned int), cudaMemcpyHostToDevice);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMemcpy failed!");
		goto Error;
	}

	cudaStatus = cudaMemcpy(dev_pierwsza, pierwsza, sizeof(bool), cudaMemcpyHostToDevice);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMemcpy failed!");
		goto Error;
	}

	// SPRAWDZENIE PATOLOGICZNYCH PRZYPADKOW
	PierwszaCzyZlozona23 << <1, 2 >> > (dev_liczba, dev_pierwsza);

	if (*pierwsza) {
		// PRZYGOTOWANIE DO PODZIALU NA SIATKI BLOKOW I BLOKI WATKOW
		int ilosc_watkow_w_bloku = 1024;
		int ilosc_blokow_w_siatce = 65535;
		long long unsigned int ilosc_iteracji = (sqrt(liczba) + 1) / 6;
		//cout << "ilosc iteracji  " << ilosc_iteracji << endl;
		long long unsigned int ilosc_pelnych_blokow = ilosc_iteracji / ilosc_watkow_w_bloku;
		//cout << "ilosc_pelnych_blokow  " << ilosc_pelnych_blokow << endl;
		long long unsigned int ilosc_watkow_w_niepelnym_bloku = ilosc_iteracji % ilosc_watkow_w_bloku;
		//cout << "ilosc_watkow_w_niepelnym_bloku  " << ilosc_watkow_w_niepelnym_bloku << endl;
		long long unsigned int ilosc_blokow = (ilosc_watkow_w_niepelnym_bloku == 0) ? ilosc_pelnych_blokow : ilosc_pelnych_blokow + 1;
		//cout << "ilosc_blokow  " << ilosc_blokow << endl;

		long long unsigned int ilosc_pelnych_siatek = ilosc_blokow / ilosc_blokow_w_siatce;
		//cout << "ilosc_pelnych_siatek  " << ilosc_pelnych_siatek << endl;
		long long unsigned int ilosc_blokow_w_niepelnej_siatce = ilosc_blokow % ilosc_blokow_w_siatce;
		//cout << "ilosc_blokow_w_niepelnej_siatce  " << ilosc_blokow_w_niepelnej_siatce << endl;
		long long unsigned int ilosc_siatek = (ilosc_blokow_w_niepelnej_siatce == 0) ? ilosc_pelnych_siatek : ilosc_pelnych_siatek + 1;
		//cout << "ilosc_siatek  " << ilosc_siatek << endl;

		cudaStatus = cudaMalloc((void**)&dev_przesuniecie, sizeof(long long unsigned int));
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaMalloc failed!");
			goto Error;
		}

		cudaStatus = cudaMemcpy(dev_przesuniecie, &przesuniecie, sizeof(long long unsigned int), cudaMemcpyHostToDevice);
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaMemcpy failed!");
			goto Error;
		}

		for (long long unsigned int i = 0; i < ilosc_siatek; i++) {
			przesuniecie = i * ilosc_blokow_w_siatce*ilosc_watkow_w_bloku;
			cudaStatus = cudaMemcpy(dev_przesuniecie, &przesuniecie, sizeof(long long unsigned int), cudaMemcpyHostToDevice);
			if (cudaStatus != cudaSuccess) {
				fprintf(stderr, "cudaMemcpy failed!");
				goto Error;
			}

			if (i == ilosc_siatek - 1) {
				// PRZYPADEK W KTORYM BADAMY NIEPELNA SIATKE Z PELNYMI BLOKAMI
				if (ilosc_blokow_w_niepelnej_siatce > 1) {
					PierwszaCzyZlozona << <ilosc_blokow_w_niepelnej_siatce - 1, ilosc_watkow_w_bloku >> > (dev_liczba, dev_pierwsza, dev_przesuniecie);
					if (!*pierwsza)
						break;

					przesuniecie += (ilosc_blokow_w_niepelnej_siatce - 1)*ilosc_watkow_w_bloku;
					cudaStatus = cudaMemcpy(dev_przesuniecie, &przesuniecie, sizeof(long long unsigned int), cudaMemcpyHostToDevice);
					if (cudaStatus != cudaSuccess) {
						fprintf(stderr, "cudaMemcpy failed!");
						goto Error;
					}
				}
				// PRZYPADEK W KTORYM BADAMY NIEPELNY BLOK
				PierwszaCzyZlozona << <1, ilosc_watkow_w_niepelnym_bloku >> > (dev_liczba, dev_pierwsza, dev_przesuniecie);
			}
			else
				// PRZYPADEK W KTORYM BADAMY PELNA SIATKE Z PELNYMI BLOKAMI
				PierwszaCzyZlozona << <ilosc_blokow_w_siatce, ilosc_watkow_w_bloku >> > (dev_liczba, dev_pierwsza, dev_przesuniecie);

			if (!*pierwsza)
				break;
		}
	}

	cudaStatus = cudaGetLastError();
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "addKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
		goto Error;
	}

	cudaStatus = cudaDeviceSynchronize();
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
		goto Error;
	}

	cudaStatus = cudaMemcpy(pierwsza, dev_pierwsza, sizeof(bool), cudaMemcpyDeviceToHost);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMemcpy failed!");
		goto Error;
	}


Error:

	cudaFree(dev_liczba);
	cudaFree(dev_pierwsza);
	cudaFree(dev_przesuniecie);

	return cudaStatus;
}

