#!python
#cython: boundscheck=False
#cython: wraparound=False
#cython: initializedcheck=False
#cython: cdivision=True
cimport mpi4py.libmpi as mpi
cimport Grid
cimport ReferenceState
cimport ParallelMPI
cimport TimeStepping
cimport Radiation
cimport Surface
from NetCDFIO cimport NetCDFIO_Stats
import cython

cimport numpy as np
import numpy as np
include "parameters.pxi"

import cython

def SurfaceBudgetFactory(namelist):
    if namelist['meta']['casename'] == 'ZGILS':
        return SurfaceBudget(namelist)
    else:
        return SurfaceBudgetNone()

cdef class SurfaceBudgetNone:
    def __init__(self):
        return

    cpdef initialize(self, Grid.Grid Gr, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa):
        return
    cpdef update(self,Grid.Grid Gr, Radiation.RadiationBase Ra, Surface.SurfaceBase Sur, TimeStepping.TimeStepping TS, ParallelMPI.ParallelMPI Pa):
        return
    cpdef stats_io(self, Surface.SurfaceBase Sur, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa):
        return
    cpdef init_from_restart(self, Restart):
        return
    cpdef restart(self, Restart):
        return

cdef class SurfaceBudget:
    def __init__(self, namelist):

        try:
            self.constant_sst = namelist['surface_budget']['constant_sst']
        except:
            self.constant_sst = False

        try:
            self.ocean_heat_flux = namelist['surface_budget']['ocean_heat_flux']
        except:
            self.ocean_heat_flux = 0.0
        try:
            self.water_depth = namelist['surface_budget']['water_depth']
        except:
            self.water_depth = 1.0
        # Allow spin up time with fixed sst
        try:
            self.fixed_sst_time = namelist['surface_budget']['fixed_sst_time']
        except:
            self.fixed_sst_time = 0.0
        # try:
        #     self.constant_ohu = namelist['surface_budget']['constant_ohu']
        # except:
        #     self.constant_ohu = True
        # try:
        #     self.ohu_adjustment_timescale = namelist['surface_budget']['ohu_adjustment_timescale']
        # except:
        #     self.ohu_adjustment_timescale = 10*86400.0

        return



    cpdef initialize(self, Grid.Grid Gr,  NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa):
        NS.add_ts('surface_temperature', Gr, Pa)
        NS.add_ts('ocean_heat_flux',Gr,Pa)
        return

    cpdef update(self, Grid.Grid Gr, Radiation.RadiationBase Ra, Surface.SurfaceBase Sur,
                 TimeStepping.TimeStepping TS, ParallelMPI.ParallelMPI Pa):

        cdef:
            int root = 0
            int count = 1
            double rho_liquid = 1000.0
            double mean_shf = Pa.HorizontalMeanSurface(Gr, &Sur.shf[0])
            double mean_lhf = Pa.HorizontalMeanSurface(Gr, &Sur.lhf[0])
            double net_flux, tendency
            double toa_imbalance = Ra.toa_sw_down-Ra.toa_sw_up - Ra.toa_lw_up


        if self.constant_sst:
            return

        if TS.rk_step != 0:
            return
        if TS.t < self.fixed_sst_time:
            return

        if Pa.sub_z_rank == 0:
            # if not self.constant_ohu:
            #  quite possibly should be toa_imbalance-ref_S_minus_L_subtropical--Colleen
            #     self.ocean_heat_flux += toa_imbalance/self.ohu_adjustment_timescale * TS.dt * TS.acceleration_factor
            #


            net_flux =  -self.ocean_heat_flux - Ra.srf_lw_up - Ra.srf_sw_up - mean_shf - mean_lhf + Ra.srf_lw_down + Ra.srf_sw_down
            tendency = net_flux/4.19e3/rho_liquid/self.water_depth
            Sur.T_surface += tendency * TS.dt * TS.acceleration_factor

        mpi.MPI_Bcast(&Sur.T_surface,count,mpi.MPI_DOUBLE,root, Pa.cart_comm_sub_z)
        mpi.MPI_Bcast(&self.ocean_heat_flux,count,mpi.MPI_DOUBLE,root, Pa.cart_comm_sub_z)



        return
    cpdef stats_io(self, Surface.SurfaceBase Sur, NetCDFIO_Stats NS, ParallelMPI.ParallelMPI Pa):
        NS.write_ts('surface_temperature', Sur.T_surface, Pa)
        NS.write_ts('ocean_heat_flux', self.ocean_heat_flux, Pa)
        return
    cpdef init_from_restart(self, Restart):
        try:
            self.ocean_heat_flux = Restart.restart_data['surface_budget']['ohu']
        except:
            print('Ocean heat flux not found in restart files!')
            print('Using namelist value '+ str(self.ocean_heat_flux))
        return
    cpdef restart(self, Restart):
        Restart.restart_data['surface_budget'] = {}
        Restart.restart_data['surface_budget']['ohu'] = self.ocean_heat_flux
        return