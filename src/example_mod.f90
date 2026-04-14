module example_mod
  implicit none
  private
  public :: greet

  integer, parameter, public :: VERSION_MAJOR = 1
  integer, parameter, public :: VERSION_MINOR = 0

contains

  subroutine greet(name)
    character(len=*), intent(in) :: name
    print *, "Hello, ", trim(name), "!"
  end subroutine greet

end module example_mod
