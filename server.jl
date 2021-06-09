using HTTP
using HTTP.Sockets
using Workspace
s = Workspace.Session()
router = Workspace.make_router(s)
HTTP.serve(router, Sockets.localhost, 8081)
