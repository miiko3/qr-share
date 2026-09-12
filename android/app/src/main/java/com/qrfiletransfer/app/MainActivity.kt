package com.qrfiletransfer.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.qrfiletransfer.app.ui.HomeScreen
import com.qrfiletransfer.app.ui.ReceiveScreen
import com.qrfiletransfer.app.ui.SendScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { App() }
    }
}

@Composable
private fun App() {
    var screen by remember { mutableStateOf("home") }
    MaterialTheme {
        Surface(Modifier.fillMaxSize()) {
            when (screen) {
                "send" -> SendScreen(onBack = { screen = "home" })
                "receive" -> ReceiveScreen(onBack = { screen = "home" })
                else -> HomeScreen(
                    onSend = { screen = "send" },
                    onReceive = { screen = "receive" }
                )
            }
        }
    }
}