// expect: Socket functions
int OnInit(){ int s=SocketCreate(); SocketConnect(s,"x",80,100); return(INIT_SUCCEEDED);}
