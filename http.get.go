package main

import (
"fmt"
"net/http"
"io/ioutil"
"os"
)

func main(){

if len(os.Args) != 2 {
  fmt.Fprintf(os.Stderr, "Usage: %s URL\n", os.Args[0])
  os.Exit(1)
}

response, err := http.Get(os.Args[1])
if err != nil {
  fmt.Printf("%s", err)
  os.Exit(1)
} else {
  defer response.Body.Close()
  contents, err := ioutil.ReadAll(response.Body)
  if err != nil {
    fmt.Printf("%s", err)
    os.Exit(1)
  }
  fmt.Printf("%s\n", string(contents))
}

}
