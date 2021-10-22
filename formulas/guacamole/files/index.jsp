<%
  final String redirectURL = "/guacamole/";
  response.setStatus(response.SC_MOVED_PERMANENTLY);
  response.sendRedirect(redirectURL);
%>