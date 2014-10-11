part of github.common;

/// Internal Helper for dealing with GitHub Pagination.
class PaginationHelper<T> {
  final GitHub github;
  
  PaginationHelper(this.github);
  
  Future<List<http.Response>> fetch(String method, String path, {int pages, Map<String, String> headers, Map<String, dynamic> params, String body}) {
    var completer = new Completer();
    var responses = [];
    if (headers == null) headers = {};
    Future<http.Response> actualFetch(String realPath) {
      return github.request(method, realPath, headers: headers, params: params, body: body);
    }
    
    void done() => completer.complete(responses);
    
    var count = 0;
    
    var handleResponse;
    handleResponse = (http.Response response) {
      count++;
      responses.add(response);
      
      if (!response.headers.containsKey("link")) {
        done();
        return;
      }
      
      var info = parseLinkHeader(response.headers['link']);
      
      if (!info.containsKey("next")) {
        done();
        return;
      }
      
      if (pages != null && count == pages) {
        done();
        return;
      }
      
      var nextUrl = info['next'];
      
      actualFetch(nextUrl).then(handleResponse);
    };
    
    actualFetch(path).then(handleResponse);
    
    return completer.future;
  }
  
  Stream<http.Response> fetchStreamed(String method, String path, {int pages, bool reverse: false, int start, Map<String, String> headers, Map<String, dynamic> params, String body}) {
    if (headers == null) headers = {};
    var controller = new StreamController.broadcast();
    
    Future<http.Response> actualFetch(String realPath, [bool first = false]) {
      var p = params;
      
      if (first && start != null) {
        p = new Map.from(params);
        p['page'] = start;
      }
      
      return github.request(method, realPath, headers: headers, params: p, body: body);
    }
    
    var count = 0;
    
    var handleResponse;
    handleResponse = (http.Response response) {
      count++;
      controller.add(response);
      
      if (!response.headers.containsKey("link")) {
        controller.close();
        return;
      }
      
      var info = parseLinkHeader(response.headers['link']);
      
      if (!info.containsKey(reverse ? "prev" : "next")) {
        controller.close();
        return;
      }
      
      if (pages != null && count == pages) {
        controller.close();
        return;
      }
      
      var nextUrl = reverse ? info['prev'] : info['next'];
      
      actualFetch(nextUrl).then(handleResponse);
    };
    
    actualFetch(path, true).then((response) {
      if (count == 0 && reverse) {
        var info = parseLinkHeader(response.headers['link']);
        if (!info.containsKey("last")) {
          controller.close();
          return;
        }
        actualFetch(info['last'], true);
      } else {
        handleResponse(response);
      }
    });
    
    return controller.stream;
  }
  
  Stream<T> objects(String method, String path, JSONConverter converter, {int pages, bool reverse: false, int start, Map<String, String> headers, Map<String, dynamic> params, String body}) {
    if (headers == null) headers = {};
    headers.putIfAbsent("Accept", () => "application/vnd.github.v3+json");
    var controller = new StreamController();
    fetchStreamed(method, path, pages: pages, start: start, reverse: reverse, headers: headers, params: params, body: body).listen((response) {
      var json = response.asJSON();
      for (var item in json) {
        controller.add(converter(item));
      }
    }).onDone(() => controller.close());
    return controller.stream;
  }
}