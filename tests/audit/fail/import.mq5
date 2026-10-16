// expect: #import
#import "user32.dll"
int MessageBoxW(int,string,string,int);
#import
int OnInit(){return(INIT_SUCCEEDED);}
