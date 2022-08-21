package hello

import (
	"fmt"
	"net/http"
)

func HelloWorld(w http.ResponseWriter, r *http.Request) {
	header := r.Header
	fmt.Fprintf(w, "%s", header["Authorization"])
}
