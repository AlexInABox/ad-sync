from tkinter import StringVar, TOP
from tkinterdnd2 import TkinterDnD, DND_ALL
import webbrowser
import customtkinter
import subprocess
import threading
import time


class CTk(customtkinter.CTk, TkinterDnD.DnDWrapper):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.TkdndVersion = TkinterDnD._require(self)

customtkinter.set_ctk_parent_class(TkinterDnD.Tk)
customtkinter.set_appearance_mode("System")  # Modes: "System" (standard), "Dark", "Light"
customtkinter.set_default_color_theme("blue")  # Themes: "blue" (standard), "green", "dark-blue"

class App(customtkinter.CTk):
    

    def __init__(self):
        super().__init__()

        # configure window
        self.title("ad-sync - Active Directory Synchronization")
        self.geometry(f"{1100}x{580}")
        #set the minimum size of the window
        self.minsize(625, 440)

        # configure grid layout (4x4)
        self.grid_columnconfigure(1, weight=1)
        self.grid_columnconfigure((2), weight=0)
        self.grid_rowconfigure((0, 1), weight=1)

        # create sidebar frame with widgets
        self.sidebar_frame = customtkinter.CTkFrame(self, width=140, corner_radius=0)
        self.sidebar_frame.grid(row=0, column=0, rowspan=4, sticky="nsew")
        self.sidebar_frame.grid_rowconfigure(4, weight=1)
        self.logo_label = customtkinter.CTkLabel(self.sidebar_frame, text="ad-sync", font=customtkinter.CTkFont(size=20, weight="bold"))
        self.logo_label.grid(row=0, column=0, padx=20, pady=(20, 10))
        self.sidebar_button_1 = customtkinter.CTkButton(self.sidebar_frame, command=self.githubButtonClick, text="GitHub")
        self.sidebar_button_1.grid(row=1, column=0, padx=20, pady=10)
        self.appearance_mode_label = customtkinter.CTkLabel(self.sidebar_frame, text="Appearance Mode:", anchor="w")
        self.appearance_mode_label.grid(row=5, column=0, padx=20, pady=(10, 0))
        self.appearance_mode_optionemenu = customtkinter.CTkOptionMenu(self.sidebar_frame, values=["Light", "Dark", "System"], command=self.change_appearance_mode_event)
        self.appearance_mode_optionemenu.grid(row=6, column=0, padx=20, pady=(10, 10))
        self.scaling_label = customtkinter.CTkLabel(self.sidebar_frame, text="UI Scaling:", anchor="w")
        self.scaling_label.grid(row=7, column=0, padx=20, pady=(10, 0))
        self.scaling_optionemenu = customtkinter.CTkOptionMenu(self.sidebar_frame, values=["80%", "90%", "100%", "110%", "120%"],
                                                               command=self.change_scaling_event)
        self.scaling_optionemenu.grid(row=8, column=0, padx=20, pady=(10, 20))

        # create main entry and button
        self.entry = customtkinter.CTkEntry(self, placeholder_text="./main.ps1 -configPath config.json -tablePath table.csv -debugEnabled 1")
        self.entry.grid(row=3, column=1, columnspan=2, padx=(20, 0), pady=(20, 20), sticky="nsew")

        self.main_button_1 = customtkinter.CTkButton(master=self, command=self.startSyncProcess)
        self.main_button_1.grid(row=3, column=3, padx=(20, 20), pady=(20, 20), sticky="nsew")

        # create textbox
        self.textbox = customtkinter.CTkTextbox(self, width=250)
        self.textbox.grid(row=0, rowspan=2, column=1, padx=(20, 0), pady=(20, 0), sticky="nsew")

        # create tabview
        self.tabview = customtkinter.CTkTabview(self, width=400, height=390)
        self.tabview.grid(row=0, column=2, columnspan=2, padx=(20, 20), pady=(20, 0), sticky="nsew")
        self.tabview.add("Set input files")
        self.tabview.add("Preview config")
        self.tabview.add("Preview table")
        self.tabview.tab("Set input files").grid_columnconfigure(0, weight=1)  # configure grid of individual tabs
        self.tabview.tab("Preview config").grid_columnconfigure(0, weight=1)

        #File Picker
        def updateEntry():
            self.entry.configure(state="normal")
            self.entry.configure(placeholder_text="./main.ps1 -configPath \"" + self.config_picker.get() + "\" -tablePath \"" + self.table_picker.get() + "\" -debugEnabled " + str(self.checkbox_1.get()))
            self.entry.configure(state="disabled")

        def getPathFromEvent(event):
            return event.data

        def checkIfJSON(event):
            path = getPathFromEvent(event)
            tkinterPath = StringVar()
            tkinterPath.set(path)
            if path.endswith(".json") or path.endswith(".JSON"):
                self.configPathLabel.configure(text="Yippie!  I accept this config for now :3", text_color="green")
                self.config_picker.configure(textvariable=tkinterPath)
            else:
                self.config_picker.configure(textvariable=StringVar())
                self.configPathLabel.configure(text="The config file must be in JSON format", text_color="red")
            updateEntry()

        def checkIfCSV(event):
            path = getPathFromEvent(event)
            tkinterPath = StringVar()
            tkinterPath.set(path)
            if path.endswith(".csv") or path.endswith(".CSV"):
                self.tablePathLabel.configure(text="Yippie!  I accept this table for now :3", text_color="green")
                self.table_picker.configure(textvariable=tkinterPath)
            else:
                self.table_picker.configure(textvariable=StringVar())
                self.tablePathLabel.configure(text="The input table file must be in CSV format", text_color="red")
            updateEntry()

        self.config_picker = customtkinter.CTkEntry(master=self.tabview.tab("Set input files"))
        self.config_picker.pack(pady=10, padx=10)

        self.configPathLabel = customtkinter.CTkLabel(master=self.tabview.tab("Set input files"), text="Drag & Drop the config file here")
        self.configPathLabel.pack(side=TOP, pady=(0, 30))

        self.table_picker = customtkinter.CTkEntry(master=self.tabview.tab("Set input files"))
        self.table_picker.pack(pady=10, padx=10)

        self.tablePathLabel = customtkinter.CTkLabel(master=self.tabview.tab("Set input files"), text="Drag & Drop the input table file here")
        self.tablePathLabel.pack(side=TOP)

        self.config_picker.drop_target_register(DND_ALL)
        self.config_picker.dnd_bind("<<Drop>>", checkIfJSON)

        self.table_picker.drop_target_register(DND_ALL)
        self.table_picker.dnd_bind("<<Drop>>", checkIfCSV)

        #Preview Config
        def loadConfig():
            try:
                with open(self.config_picker.get(), "r") as file:
                    self.configPreview.configure(state="normal")
                    self.configPreview.delete("0.0", "end")
                    self.configPreview.insert("0.0", file.read())
                    self.configPreview.configure(state="disabled")
            except:
                self.configPreview.configure(state="normal")
                self.configPreview.delete("0.0", "end")
                self.configPreview.insert("0.0", "Error loading the config file")
                self.configPreview.configure(state="disabled")

        self.configPreview = customtkinter.CTkTextbox(master=self.tabview.tab("Preview config"), width=350, height=320)
        self.configPreview.pack(pady=10, padx=10)
        self.configPreview.insert("0.0", "Preview of the config file")
        self.tabview.tab("Preview config").bind("<Visibility>", lambda event: loadConfig())

        #Preview table
        def loadTable():
            try:
                with open(self.table_picker.get(), "r") as file:
                    self.tablePreview.configure(state="normal")
                    self.tablePreview.delete("0.0", "end")
                    for i in range(10):
                        self.tablePreview.insert("end", file.readline())
                    self.tablePreview.insert("end", "...")
                    self.tablePreview.configure(state="disabled")
            except:
                self.tablePreview.configure(state="normal")
                self.tablePreview.delete("0.0", "end")
                self.tablePreview.insert("0.0", "Error loading the table file")
                self.tablePreview.configure(state="disabled")

        self.tablePreview = customtkinter.CTkTextbox(master=self.tabview.tab("Preview table"), width=350, height=320)
        self.tablePreview.pack(pady=10, padx=10)
        self.tablePreview.insert("0.0", "Preview of the table file")
        self.tabview.tab("Preview table").bind("<Visibility>", lambda event: loadTable())

        # create checkbox and switch frame
        self.checkbox_slider_frame = customtkinter.CTkFrame(self, height=50)
        self.checkbox_slider_frame.grid(row=1, column=2, columnspan=2, padx=(20, 20), pady=(20, 0), sticky="nsew")
        self.checkbox_1 = customtkinter.CTkCheckBox(master=self.checkbox_slider_frame, command=updateEntry)
        self.checkbox_1.grid(row=1, column=0, pady=(20, 0), padx=20, sticky="n")

        # set default values
        self.appearance_mode_optionemenu.set("Dark")
        self.scaling_optionemenu.set("100%")
        self.entry.configure(state="disabled")
        self.textbox.insert("0.0", "ad-sync log:\n\n" + "Don't do the cat!\n" * 40)
        self.textbox.configure(state="disabled")
        self.configPreview.configure(state="disabled")
        self.tablePreview.configure(state="disabled")
        self.checkbox_1.configure(text="Debug?")
        self.checkbox_1.select()
        self.main_button_1.configure(fg_color="transparent", border_width=2, text_color=("gray10", "#DCE4EE"), text="Sync Active Directory")

    def change_appearance_mode_event(self, new_appearance_mode: str):
        customtkinter.set_appearance_mode(new_appearance_mode)

    def change_scaling_event(self, new_scaling: str):
        new_scaling_float = int(new_scaling.replace("%", "")) / 100
        customtkinter.set_widget_scaling(new_scaling_float)
        
    def githubButtonClick(self):
        print("GitHub Button was clicked! Yippie!")
        #Open the GitHub Repository in the default browser
        webbrowser.open_new("https://github.com/alexinabox/ad-sync")

    def startSyncProcess(self):
        self.main_button_1.configure(state="disabled")
        print("Sync Active Directory Button was clicked! Yippie!")

        #Check if the config and table file are set
        #Update one last time
        self.entry.configure(state="normal")
        self.entry.configure(placeholder_text="./main.ps1 -configPath \"" + self.config_picker.get() + "\" -tablePath \"" + self.table_picker.get() + "\" -debugEnabled " + str(self.checkbox_1.get()))
        self.entry.configure(state="disabled")
        
        if (self.config_picker.get() == "" or self.table_picker.get() == ""):
            self.textbox.configure(state="normal")
            self.textbox.delete("0.0", "end")
            self.textbox.insert("0.0", "Please set the config and table file first")
            self.textbox.configure(text_color="red")
            self.textbox.configure(state="disabled")
            self.main_button_1.configure(state="normal")
            return
        
        #Execute command that sits in the entry field as a placeholder
        self.textbox.configure(text_color=("black", "white"))
        command = self.entry.cget("placeholder_text")
        print(command)
        self.textbox.configure(state="normal")
        self.textbox.delete("0.0", "end")
        self.textbox.configure(state="disabled")

        def refreshLog(log):
            self.textbox.configure(state="normal")
            self.textbox.delete("0.0", "end")
            self.textbox.insert("0.0", log)
            self.textbox.configure(state="disabled")
            self.main_button_1.configure(state="normal")
        def appendLog(log):
            self.textbox.configure(state="normal")
            self.textbox.insert("end", log)
            self.textbox.configure(state="disabled")
        #Start a thread that reads the log file and updates the textbox every second
        
        commandFinished = threading.Event()
        def executeCommand():
            subprocess.call(["powershell.exe", command])
            time.sleep(1) #Delay the termination of the thread to ensure the log file is read completely
            commandFinished.set()
            
        def readLogFile(self, refreshLog):
            log = ""
            while not commandFinished.is_set():
                try:
                    with open("./modules/debug.log", "r") as file:
                        log = file.read()
                except:
                    log = "Error reading the log file"
                if log != self.textbox.get("0.0", "end"):
                    refreshLog(log)
                time.sleep(1)
            appendLog("\n\nScript execution finished\n")

        threading.Thread(target=executeCommand).start()
        threading.Thread(target=readLogFile, args=(self, refreshLog)).start()



if __name__ == "__main__":
    app = App()
    app.mainloop()