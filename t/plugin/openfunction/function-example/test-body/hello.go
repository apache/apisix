package hello

import (
	"fmt"
	"net/http"
	"io/ioutil"
	"github.com/OpenFunction/functions-framework-go/functions"
)

func init() {
	functions.HTTP("HelloWorld", HelloWorld)
}

func HelloWorld(w http.ResponseWriter, r *http.Request) {
	body,_ := ioutil.ReadAll(r.Body)
	fmt.Fprintf(w, "Hello, %s!\n", string(body))
}
