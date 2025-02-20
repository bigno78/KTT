#define IN_RANGE(x, min, max)   ((x)>=(min) && (x)<=(max))
#define BLOCK_SIZE_REF 16 //has to be the value as in hotspot_reference.h

extern "C" __global__ void hotspot(  int iteration,
                                float *power,
                                float *temp_src,
                                float *temp_dst,
                               int grid_cols,
                               int grid_rows,
							   int border_cols,
							   int border_rows,
                               float Cap,
                               float Rx, 
                               float Ry, 
                               float Rz, 
                               float step) {
	
	__shared__ float temp_on_cuda[BLOCK_SIZE_REF][BLOCK_SIZE_REF];
	__shared__ float power_on_cuda[BLOCK_SIZE_REF][BLOCK_SIZE_REF];
	__shared__ float temp_t[BLOCK_SIZE_REF][BLOCK_SIZE_REF]; // saving temporary temperature result

	float amb_temp = 80.0f;
	float step_div_Cap;
	float Rx_1,Ry_1,Rz_1;

	int bx = blockIdx.x;
	int by = blockIdx.y;

	int tx = threadIdx.x;
	int ty = threadIdx.y;

	step_div_Cap=step/Cap;

	Rx_1=1/Rx;
	Ry_1=1/Ry;
	Rz_1=1/Rz;

	// each block finally computes result for a small block
	// after N iterations. 
	// it is the non-overlapping small blocks that cover 
	// all the input data

	// calculate the small block size
	int small_block_rows = BLOCK_SIZE_REF-iteration*2;//EXPAND_RATE
	int small_block_cols = BLOCK_SIZE_REF-iteration*2;//EXPAND_RATE

	// calculate the boundary for the block according to 
	// the boundary of its small block
	int blkY = small_block_rows*by-border_rows;
	int blkX = small_block_cols*bx-border_cols;
	int blkYmax = blkY+BLOCK_SIZE_REF-1;
	int blkXmax = blkX+BLOCK_SIZE_REF-1;

	// calculate the  thread coordination
	int yidx = blkY+ty;
	int xidx = blkX+tx;

	// load data if it is within the valid input range
	int loadYidx=yidx, loadXidx=xidx;
	int index = grid_cols*loadYidx+loadXidx;
       
	if(IN_RANGE(loadYidx, 0, grid_rows-1) && IN_RANGE(loadXidx, 0, grid_cols-1)){
            temp_on_cuda[ty][tx] = temp_src[index];  // Load the temperature data from  memory to shared memory
            power_on_cuda[ty][tx] = power[index];// Load the power data from  memory to shared memory
	}
	__syncthreads();

	// effective range within this block that falls within 
	// the valid range of the input data
	// used to rule out computation outside the boundary.
	int validYmin = (blkY < 0) ? -blkY : 0;
	int validYmax = (blkYmax > grid_rows-1) ? BLOCK_SIZE_REF-1-(blkYmax-grid_rows+1) : BLOCK_SIZE_REF-1;
	int validXmin = (blkX < 0) ? -blkX : 0;
	int validXmax = (blkXmax > grid_cols-1) ? BLOCK_SIZE_REF-1-(blkXmax-grid_cols+1) : BLOCK_SIZE_REF-1;

	int N = ty-1;
	int S = ty+1;
	int W = tx-1;
	int E = tx+1;

	N = (N < validYmin) ? validYmin : N;
	S = (S > validYmax) ? validYmax : S;
	W = (W < validXmin) ? validXmin : W;
	E = (E > validXmax) ? validXmax : E;

	bool computed;
	for (int i=0; i<iteration ; i++){ 
		computed = false;
		if( IN_RANGE(tx, i+1, BLOCK_SIZE_REF-i-2) &&  \
		IN_RANGE(ty, i+1, BLOCK_SIZE_REF-i-2) &&  \
		IN_RANGE(tx, validXmin, validXmax) && \
		IN_RANGE(ty, validYmin, validYmax) ) {
			computed = true;
			temp_t[ty][tx] =   temp_on_cuda[ty][tx] + step_div_Cap * (power_on_cuda[ty][tx] + 
			(temp_on_cuda[S][tx] + temp_on_cuda[N][tx] - 2.0f * temp_on_cuda[ty][tx]) * Ry_1 + 
			(temp_on_cuda[ty][E] + temp_on_cuda[ty][W] - 2.0f * temp_on_cuda[ty][tx]) * Rx_1 + 
			(amb_temp - temp_on_cuda[ty][tx]) * Rz_1);
		}
		__syncthreads();
		
		if(i==iteration-1)
			break;
		if(computed)	 //Assign the computation range
			temp_on_cuda[ty][tx]= temp_t[ty][tx];
			
		__syncthreads();
	}

	// update the  memory
	// after the last iteration, only threads coordinated within the 
	// small block perform the calculation and switch on ``computed''
	if (computed){
	  temp_dst[index]= temp_t[ty][tx];		
	}
}
