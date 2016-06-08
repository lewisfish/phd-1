module main
implicit none
contains
subroutine mcpolar(conc, id1, id2, id3, error, numproc, id, pflag)

!external libs
use mpi

!shared data
use constants
use photon_vars
use iarray
use opt_prop

!subroutines
use subs
use reader_mod
use gridset_mod
use sourceph_mod
use noisey_mod
use tauint
use ch_opt
use stokes_mod
use binning_mod
use peelingoff_mod
use writer_mod

implicit none

integer :: nphotons,iseed,j,xcell,ycell,zcell,flucount,nlow,id1, id2, id3
logical :: tflag,sflag,fflag,pflag
DOUBLE PRECISION :: ddy,ddx,nscatt,n1,n2,weight,val,fluro_prob
DOUBLE PRECISION :: delta,xcur,ycur,zcur,thetaim,ran 

DOUBLE PRECISION :: ddz,ddr,v(3), conc(3)
DOUBLE PRECISION :: costim,cospim,sintim,sinpim
DOUBLE PRECISION :: phiim
real :: start,finish,ran2,sleft,fleft,time

!      variables for openmpi. GLOBAL indicates final values after mpi reduce
!      numproc is number of process being run, id is the indivdual id of each process
!      error is the error flag for MPI

DOUBLE PRECISION :: nscattGLOBAL
integer          :: error,numproc,id
character(len=1) :: fn

!print*,conc

!set directory paths
!call directory(id)

call alloc_array
call zarray

! init mpi
!      call MPI_init(error)
!! get number of processes
!      call MPI_Comm_size(MPI_COMM_WORLD,numproc,error)
!! get individual process id
!      call MPI_Comm_rank(MPI_COMM_WORLD,id,error)

!**** Read in parameters from the file input.params
open(10,file=trim(resdir)//'input.params',status='old')
    read(10,*) nphotons
    read(10,*) xmax
    read(10,*) ymax
    read(10,*) zmax
    read(10,*) n1
    read(10,*) n2
    close(10)

! set seed for rnd generator. id to change seed for each process
iseed=95648324+id

!conc(1) = 1.0d-3 !target values!!!!
!conc(2) = 1.0d-4
!conc(3) = 1.0d-5

!conc(1) =    9.9507762074470523E-004
!    !target values!!!!
!conc(2) = 1.0124113053083419E-004

!conc(3) =    1.1900707788765430E-004
!   5.6493969500064848E-004
!   7.2375282272696493E-005
!   6.0100973807275293E-005

! conc(1)=  5.7987542033195499E-004
!   conc(2)=6.9989011436700826E-005
!   conc(3)=8.2174995094537738E-005

!read in optical property data
!call reader1
acount=0
fcount=0

!****** setup up arrays and bin numbers/dimensions

!set bin widths for deposit method
ddz=(2.*zmax)/cbinsnum
ddx=(2.*xmax)/cbinsnum
ddy=(2.*ymax)/cbinsnum
ddr=(ymax)/(cbinsnum)

!***** Set up constants, pi and 2*pi  ********************************

iseed=-abs(iseed)  ! Random number seed must be negative for ran2
flucount=0

! postion image in degrees
phiim=0.*pi/180.
thetaim=0.*pi/180.

!     image postion vector
!angle for vector
sintim=sin(thetaim)
sinpim=sin(phiim)
costim=cos(thetaim)
cospim=cos(phiim)

!vector
v(1)=sintim*cospim     
v(2)=sintim*sinpim
v(3)=costim  

!set optical properties and make cdfs.
wave=260. 

! create cdfs to sample from
call mk_cdf(nadh_fluro, nadh_cdf, size(nadh_fluro, 1))
call mk_cdf(ribo_fluro, ribo_cdf, size(ribo_fluro, 1))
call mk_cdf(tyro_fluro, tyro_cdf, size(tyro_fluro, 1))
call init_opt(conc)

! calculate number of photons to be run over all cores.  
!if(id.eq.0)then
!   print*, ''      
!   print*,'# of photons to run',nphotons*numproc
!end if

!***** Set up density grid *******************************************
call gridset(id)

!***** Set small distance for use in optical depth integration routines 
!***** for roundoff effects when crossing cell walls
delta=1.e-6*(2.*xmax/nxg)
nscatt=0
tcount=0

call MPI_Barrier(MPI_COMM_WORLD,error)
call cpu_time(start)
!print*, ' '
!print*, 'Photons now running on core:',id
call cpu_time(sleft)


!loop over photons   
do j=1,nphotons
  
!set init weight and flags
   wave=260.
   call init_opt(conc)
   tflag=.FALSE.
   fflag=.FALSE.
   sflag=.TRUE.     ! flag for fresnel subroutine. so that incoming photons
                       ! are treated diffrently to outgoing ones

! code to output progress as program runs also gives an estimate of when program will complete.
   if(mod(j,int(0.02d0*nphotons)).eq.0)then
      if(id.eq.0.and.pflag)then
            write(*,FMT="(A1,A,t21,F6.2,A)",ADVANCE="NO") achar(13), &
                " Percent Complete: ", (real(j)/real(nphotons))*100.0, "%"
      end if
   end if
   if(id.eq.0)then
   if (j.eq.1000.and.pflag)then
      call cpu_time(fleft)
      time = ((fleft-sleft)/1000.)*real(nphotons)
      print*,' '
      if(time.ge.60.)then
         print'(A, I3, 1X, A)','Approx time program will take to run: ',floor((time)/60.d0),'mins'
      else
         print'(A, 1X, I2, A)', 'Approx time program will take to run:',floor(time),'s'
      end if
!         print*,' '
   end if
   end if

   
!***** Release photon from point source *******************************
   call sourceph(xcell,ycell,zcell,iseed)

!***** Update xcur etc.
   xcur=xp+xmax
   ycur=yp+ymax
   zcur=zp+zmax

!***** Generate new normal corresponding to bumpy surface
!   call noisey(xcell,ycell)

!***** check whether the photon enters medium     
!   call fresnel(n1,n2,sflag,tflag,iseed,ddx,ddy,weight,xcur,ycur)
!   sflag=.FALSE.

!****** Find scattering location
   call tauint2(n1,n2,xcell,ycell,zcell,&
   tflag,iseed,delta,sflag,weight,ddx,ddy)
     
!************ Peel off photon into image
!   call peelingoff(xcell,ycell,zcell,delta, &
!   v,sintim,costim,sinpim,cospim)

!******** Photon scatters in grid until it exits (tflag=TRUE) 
   do while(tflag.eqv..FALSE.) 

!******** Scatter or absorb/fluro

! Select albedo based on current photon wavelength
      ran=ran2(iseed)
      if(ran.lt.albedo)then !photons scatters
         call stokes(iseed)
         nscatt=nscatt+1
      else !photon absorbs
!         print*, 'wave before',wave
        if( ran .lt. mua_nadh / kappa + albedo)then
            call sample(nadh_fluro, nadh_cdf, wave, iseed)
            call init_opt(conc)
!                     print*, 'wave nadh',wave
        elseif( ran .lt. (mua_nadh + mua_ribo) / kappa + albedo)then
            call sample(ribo_fluro, ribo_cdf, wave, iseed)
            call init_opt(conc)
!                     print*, 'wave ribo',wave
       elseif( ran .lt. (mua_nadh + mua_ribo + mua_tyro) / kappa + albedo)then
            call sample(tyro_fluro, tyro_cdf, wave, iseed)
            call init_opt(conc)
!                     print*, 'wave tyro',wave
         else
            tflag = .TRUE.
         end if
      end if
!maxval(excite_array,2) gives wavelength col
!minval(maxval(excite_array,2)) gives min in wavelength col

!******** Drop weight in appro bin
!      call binning(ddr,zcur,ddz,absorb)

!************ Find next scattering location
      call tauint2(n1,n2,xcell,ycell,zcell,&
   tflag,iseed,delta,sflag,weight,ddx,ddy)

!************ Peel off photon into image
!      call peelingoff(xcell,ycell,zcell,delta &
!      ,v,sintim,costim,sinpim,cospim)

      xcur=xp+xmax
      ycur=yp+ymax
      zcur=zp+zmax

   end do
!bin photons leaving top surface if they are collected by fibre
   if(int(wave).ne.260..and.zp.ge.zmax*.999)then
      flucount=flucount+1
      fluroexit(int(wave))=fluroexit(int(wave))+1
   end if
end do      ! end loop over nph photons

!print*, flucount,'# photons collected',id

!give time taken to run program
call cpu_time(finish)
!if(finish-start.ge.60.)then
! print*,floor((finish-start)/60.)+mod(finish-start,60.)/100.
!else
!      print*, 'time taken ~',floor(finish-start/60.),'s'
!end if

!force syncro
!call MPI_Barrier(MPI_COMM_WORLD,error)

!      path length reduce     
!call MPI_REDUCE(jmean,jmeanGLOBAL,((nxg+3)*(nyg+3)*(nzg+3))*4,MPI_DOUBLE_PRECISION &
!               ,MPI_SUM,0,MPI_COMM_WORLD,error)
!call MPI_Barrier(MPI_COMM_WORLD,error)

!call MPI_REDUCE(dep,depGLOBAL,cbinsnum,MPI_REAL,MPI_SUM,0,MPI_COMM_WORLD,error)
!call MPI_Barrier(MPI_COMM_WORLD,error)

!     deposit reduce
!call MPI_REDUCE(deposit,depositGLOBAL,(cbinsnum**3),MPI_REAL,MPI_SUM,0,MPI_COMM_WORLD,error)
!call MPI_Barrier(MPI_COMM_WORLD,error)
!print*,'done deposit'

!!      images reduce
!call MPI_REDUCE(image,imageGLOBAL,(Nbins**2)*4,MPI_REAL,MPI_SUM,0,MPI_COMM_WORLD,error)
!call MPI_Barrier(MPI_COMM_WORLD,error)

!     nscatt reduce
call MPI_Barrier(MPI_COMM_WORLD,error)
call MPI_REDUCE(nscatt,nscattGLOBAL,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,error)

!     trans reduce
!call MPI_Barrier(MPI_COMM_WORLD,error)
!call MPI_REDUCE(trans,transGLOBAL,nxg*nyg,MPI_REAL,MPI_SUM,0,MPI_COMM_WORLD,error)

!call MPI_Barrier(MPI_COMM_WORLD,error)
!call MPI_REDUCE(follow,followGLOBAL,(nxg)*(nyg)*(nzg),MPI_REAL,MPI_SUM,0,MPI_COMM_WORLD,error)

!     fluroexit reduce
!write(fn,"(i0,a)") id
!open(34+id,file=fn//'out.dat')
!do j=1,1000
!   write(34+id,*)fluroexit(j)
!end do

call MPI_Barrier(MPI_COMM_WORLD,error)
call MPI_REDUCE(fluroexit,fluroexitGLOBAL,1000,MPI_INTEGER,MPI_SUM,0,MPI_COMM_WORLD,error)
!     fluro_pos reduce
!call MPI_Barrier(MPI_COMM_WORLD,error)
!call MPI_REDUCE(fluro_pos,fluro_posGLOBAL,nxg*nyg*nzg,MPI_REAL,MPI_SUM,0,MPI_COMM_WORLD,error)

call MPI_Barrier(MPI_COMM_WORLD,error)
if(id.eq.0)then
!    print*,'Average # of scatters per photon:',sngl(nscattGLOBAL/(nphotons*numproc))
!    write out files
    call writer(id1, id2, id3)
end if

call dealloc_array()
call MPI_Barrier(MPI_COMM_WORLD,error)
end subroutine mcpolar
end module main
